// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";

contract DeployScriptTest is Test {
    address internal constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant POOL_MANAGER = address(0x1234);
    bytes internal constant CANONICAL_PROXY_CODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
    address internal owner;

    function setUp() public {
        vm.startBroadcast();
        owner = msg.sender;
        vm.stopBroadcast();
        vm.etch(CREATE2_PROXY, CANONICAL_PROXY_CODE);
        assertEq(CREATE2_PROXY.code.length, 69);
        vm.setEnv("POOL_MANAGER", vm.toString(POOL_MANAGER));
        vm.setEnv("OWNER", vm.toString(owner));
        vm.setEnv("WRITE_DEPLOYMENTS", "0");
    }

    function test_DeployScriptUsesCanonicalCreate2Proxy() public {
        Deploy deployer = new Deploy();
        Deploy.Deployment memory d = deployer.run();

        (address expected,) =
            _mine(abi.encodePacked(type(RudderHook).creationCode, abi.encode(IPoolManager(POOL_MANAGER), owner)));
        assertEq(d.hook, expected, "hook must land at the address mined against the canonical proxy");

        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        assertEq(uint160(d.hook) & Hooks.ALL_HOOK_MASK, flags);
        assertEq(RudderHook(d.hook).owner(), owner);
        assertEq(address(RudderHook(d.hook).poolManager()), POOL_MANAGER);
        assertEq(RudderHook(d.hook).vaultFactory(), d.factory);
        assertEq(StrategyRegistry(d.registry).factory(), d.factory);
        assertNotEq(d.vaultImplementation, address(0));
    }

    function test_DeployScriptDoesNotUseDeploySelector() public {
        bytes memory hookCode =
            abi.encodePacked(type(RudderHook).creationCode, abi.encode(IPoolManager(POOL_MANAGER), owner));
        (, bytes32 salt) = _mine(hookCode);

        vm.expectCall(CREATE2_PROXY, abi.encodePacked(salt, hookCode));
        Deploy deployer = new Deploy();
        deployer.run();
    }

    function _mine(bytes memory code) internal pure returns (address expected, bytes32 salt) {
        bytes32 codeHash = keccak256(code);
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        for (uint256 i; i < 300_000; ++i) {
            address candidate = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_PROXY, bytes32(i), codeHash))))
            );
            if (uint160(candidate) & Hooks.ALL_HOOK_MASK == flags) {
                return (candidate, bytes32(i));
            }
        }
        revert("mine failed");
    }
}
