// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";

/// @title RudderTestBase
/// @notice Shared harness. Every *usable* vault in tests is created through VaultFactory.
///         The only direct `new RudderVault()` is the locked implementation the factory clones.
abstract contract RudderTestBase is Test {
    StrategyRegistry internal registry;
    RudderVault internal vaultImpl;
    VaultFactory internal factory;
    RudderHook internal hook;

    address internal manager = address(0x1111);
    address internal owner = address(this);
    address internal curator = address(0xC0FFEE);

    function setUp() public virtual {
        registry = new StrategyRegistry();
        vaultImpl = new RudderVault();
        factory = new VaultFactory(address(vaultImpl), IPoolManager(manager), address(registry));
        hook = _deployMinedHook(manager, owner);
        hook.setVaultFactory(address(factory));
        registry.setFactory(address(factory));
    }

    /// @dev Mines a salt so the hook lands at an address whose low 14 bits exactly match the
    ///      permissions declared in RudderHook.getHookPermissions (beforeAddLiquidity + afterSwap).
    function _deployMinedHook(address _manager, address _owner) internal returns (RudderHook deployed) {
        bytes memory args = abi.encode(IPoolManager(_manager), _owner);
        bytes memory bytecode = abi.encodePacked(type(RudderHook).creationCode, args);
        uint160 requiredFlags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        uint160 flagMask = uint160(0x3FFF);

        bytes32 salt;
        address predicted;
        for (uint256 i = 0; i < 500_000; i++) {
            salt = bytes32(i);
            predicted = vm.computeCreate2Address(salt, keccak256(bytecode), address(this));
            if ((uint160(predicted) & flagMask) == requiredFlags) break;
        }
        deployed = new RudderHook{salt: salt}(IPoolManager(_manager), _owner);
        require(address(deployed) == predicted, "hook mine failed");
    }

    function _envelope() internal pure returns (Envelope memory) {
        return Envelope({
            maxRangeWidth: 1000,
            maxCenterShift: 500,
            maxTwapDistanceTicks: 1000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500
        });
    }

    function _registerStrategy(address _curator) internal returns (uint256 id) {
        vm.prank(_curator);
        id = registry.registerStrategy(_envelope());
    }

    function _poolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    /// @notice Create a vault through VaultFactory (the only supported path).
    function _createVault(uint256 strategyId, address _curator) internal returns (address vault) {
        vm.prank(_curator);
        vault = factory.createVault(strategyId, _poolKey(), 1000);
    }
}
