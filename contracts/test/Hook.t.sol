// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {RudderHook} from "../src/RudderHook.sol";

/// @dev Minimal CREATE2 deployer used to emulate deployment through the canonical deterministic
///      deployment proxy at 0x4e59b44847b379578588920cA78FbF26c0B4956C.
contract Create2Deployer {
    function deploy(bytes memory code, bytes32 salt) external returns (address addr) {
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
        }
        require(addr != address(0), "create2 failed");
    }
}

/// @notice Unit tests for the hook's ownership/initialization surface and its deployment through the
///         canonical CREATE2 proxy.
contract HookTest is Test {
    address internal constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal owner = address(0xABCD);

    function setUp() public {
        // Deploy a Create2Deployer and install its runtime at the canonical proxy address so the
        // hook is deployed exactly the way the deploy script does it.
        Create2Deployer impl = new Create2Deployer();
        vm.etch(CREATE2_PROXY, address(impl).code);
    }

    function _initCode(IPoolManager manager, address _owner) internal pure returns (bytes memory) {
        return abi.encodePacked(type(RudderHook).creationCode, abi.encode(manager, _owner));
    }

    function _mine(IPoolManager manager, address _owner)
        internal
        view
        returns (bytes32 salt, address predicted, bytes memory code)
    {
        code = _initCode(manager, _owner);
        bytes32 codeHash = keccak256(code);
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);
        uint160 mask = uint160(0x3FFF);
        for (uint256 i = 0; i < 500_000; i++) {
            address candidate = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, bytes32(i), codeHash))))
            );
            if ((uint160(candidate) & mask) == flags) {
                return (bytes32(i), candidate, code);
            }
        }
        revert("mine failed");
    }

    /// @dev Deploys a hook at a valid address from this test contract via a mined CREATE2 salt.
    function _deployHook(IPoolManager manager, address _owner) internal returns (RudderHook deployed) {
        bytes memory code = _initCode(manager, _owner);
        bytes32 codeHash = keccak256(code);
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);
        uint160 mask = uint160(0x3FFF);
        bytes32 salt;
        address predicted;
        for (uint256 i = 0; i < 500_000; i++) {
            predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(i), codeHash))))
            );
            if ((uint160(predicted) & mask) == flags) {
                salt = bytes32(i);
                break;
            }
        }
        deployed = new RudderHook{salt: salt}(manager, _owner);
        require(address(deployed) == predicted, "hook mine failed");
    }

    function test_DeployThroughCreate2Proxy() public {
        IPoolManager manager = IPoolManager(address(0x1234));
        (bytes32 salt, address predicted, bytes memory code) = _mine(manager, owner);

        address deployed = Create2Deployer(CREATE2_PROXY).deploy(code, salt);
        assertEq(deployed, predicted, "deployed hook address must match the mined address");

        RudderHook hook = RudderHook(deployed);
        assertEq(hook.owner(), owner, "constructor sets owner");
        assertEq(address(hook.poolManager()), address(manager), "constructor sets pool manager");
    }

    function test_ConstructorRejectsZeroOwner() public {
        vm.expectRevert(RudderHook.Unauthorized.selector);
        new RudderHook(IPoolManager(address(0x1234)), address(0));
    }

    function test_SetVaultFactory_OnceAndOwnerOnly() public {
        RudderHook hook = _deployHook(IPoolManager(address(0x1234)), owner);

        vm.prank(address(0xB0B));
        vm.expectRevert(RudderHook.Unauthorized.selector);
        hook.setVaultFactory(address(0xF00D));

        vm.prank(owner);
        hook.setVaultFactory(address(0xF00D));
        assertEq(hook.vaultFactory(), address(0xF00D));

        vm.prank(owner);
        vm.expectRevert(RudderHook.FactoryAlreadySet.selector);
        hook.setVaultFactory(address(0xBEEF));
    }

    function test_SetPaused_OwnerOnly() public {
        RudderHook hook = _deployHook(IPoolManager(address(0x1234)), owner);
        vm.prank(address(0xB0B));
        vm.expectRevert(RudderHook.Unauthorized.selector);
        hook.setPaused(true);

        vm.prank(owner);
        hook.setPaused(true);
        assertTrue(hook.paused());
    }
}
