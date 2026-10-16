// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderHook} from "../src/RudderHook.sol";

/// @title Deploy
/// @notice Deploys the full Rudder stack. The hook is deployed with CREATE2 (via Foundry's default
///         deterministic deployment proxy) at an address whose low 14 bits encode the required
///         permissions (beforeAddLiquidity + afterSwap). The salt is mined at runtime against the
///         SAME deployer Foundry uses for `new Hook{salt: ...}`, so the mined address always matches
///         the deployed address.
///
/// Usage:
///   POOL_MANAGER=0x00b036b58a818b1bc34d502d3fe730db729e62ac \
///     forge script contracts/script/Deploy.s.sol:Deploy \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC_URL --broadcast
contract Deploy is Script {
    /// @dev Foundry's default CREATE2 deployer used by `new C{salt: ...}` in scripts.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Unichain Sepolia v4 PoolManager (docs.uniswap.org/contracts/v4/deployments, chainId 1301).
    address internal constant UNICHAIN_SEPOLIA_POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    error HookAddressMismatch(address expected, address actual);

    struct Deployment {
        address poolManager;
        address registry;
        address vaultImplementation;
        address factory;
        address hook;
    }

    function run() external returns (Deployment memory d) {
        d.poolManager = vm.envOr("POOL_MANAGER", UNICHAIN_SEPOLIA_POOL_MANAGER);

        address owner = msg.sender;

        vm.startBroadcast();

        StrategyRegistry registry = new StrategyRegistry();
        RudderVault implementation = new RudderVault();

        // Permission bits == the bits getHookPermissions() sets to true in RudderHook.
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (address expectedHook, bytes32 salt) = _mineHook(flags, abi.encode(IPoolManager(d.poolManager), owner));

        RudderHook hook = new RudderHook{salt: salt}(IPoolManager(d.poolManager), owner);
        if (address(hook) != expectedHook) revert HookAddressMismatch(expectedHook, address(hook));

        VaultFactory factory = new VaultFactory(address(implementation), IPoolManager(d.poolManager), address(registry));

        hook.setVaultFactory(address(factory));
        // One-time owner call to authorize the factory to bind vaults to strategies.
        registry.setFactory(address(factory));

        vm.stopBroadcast();

        d.registry = address(registry);
        d.vaultImplementation = address(implementation);
        d.factory = address(factory);
        d.hook = address(hook);

        _writeDeployments(d);

        console2.log("poolManager        ", d.poolManager);
        console2.log("strategyRegistry   ", d.registry);
        console2.log("vaultImplementation", d.vaultImplementation);
        console2.log("vaultFactory       ", d.factory);
        console2.log("rudderHook         ", d.hook);
        console2.log("hook salt          ", uint256(salt));
    }

    /// @dev Mines a CREATE2 salt against `CREATE2_DEPLOYER` for the given permission flags. Runtime
    ///      mining keeps the salt in lock-step with the actual deployer (never a stale literal).
    function _mineHook(uint160 flags, bytes memory constructorArgs) internal view returns (address, bytes32) {
        bytes memory code = abi.encodePacked(type(RudderHook).creationCode, constructorArgs);
        bytes32 codeHash = keccak256(code);
        flags = flags & Hooks.ALL_HOOK_MASK;

        for (uint256 salt; salt < 300_000; ++salt) {
            address candidate = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, bytes32(salt), codeHash))))
            );
            if (uint160(candidate) & Hooks.ALL_HOOK_MASK == flags) {
                return (candidate, bytes32(salt));
            }
        }
        revert("HookMiner: could not find salt");
    }

    function _writeDeployments(Deployment memory d) internal {
        string memory obj = "rudder";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "poolManager", d.poolManager);
        vm.serializeAddress(obj, "strategyRegistry", d.registry);
        vm.serializeAddress(obj, "vaultImplementation", d.vaultImplementation);
        vm.serializeAddress(obj, "vaultFactory", d.factory);
        string memory json = vm.serializeAddress(obj, "rudderHook", d.hook);
        vm.writeJson(json, "./contracts/deployments.json");
    }
}
