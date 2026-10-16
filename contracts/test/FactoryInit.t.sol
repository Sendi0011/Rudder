// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderTestBase} from "./RudderTestBase.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";

/// @dev Implementation whose initializer always reverts, used to prove a failed initialization
///      leaves nothing registered behind.
contract BadInitVault {
    function initialize(address, address, address, uint256, address, uint16, PoolKey calldata, Envelope calldata)
        external
        pure
    {
        revert("bad init");
    }
}

contract FactoryInitTest is RudderTestBase {
    uint256 internal strategyId;

    function setUp() public override {
        super.setUp();
        strategyId = _registerStrategy(curator);
    }

    function _rawInitialize(RudderVault target, uint256 id) internal {
        target.initialize(
            address(manager), address(factory), address(registry), id, curator, 1000, _poolKey(), _envelope()
        );
    }

    function test_CreateVault_InitializesAtomically() public {
        address vault = _createVault(strategyId, curator);
        RudderVault v = RudderVault(vault);

        assertTrue(factory.isVault(vault), "factory must mark vault");
        assertEq(factory.vaultToStrategyId(vault), strategyId, "strategy binding");
        assertEq(v.curator(), curator, "curator bound at creation");
        assertEq(v.strategyId(), strategyId, "strategy id bound");
        assertEq(v.registry(), address(registry), "registry bound");
        assertEq(v.factory(), address(factory), "factory bound");
        assertEq(v.hook(), address(hook), "hook derived from pool key");
        assertEq(v.feeCapBps(), 1000, "fee cap");
        assertEq(v.totalSupply(), 0, "no shares minted at init");
    }

    function test_SecondInitializeReverts() public {
        address vault = _createVault(strategyId, curator);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _rawInitialize(RudderVault(vault), strategyId);
    }

    function test_InitializeOnBareImplementationReverts() public {
        // The implementation's constructor called _disableInitializers(), so it can never be initialized.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _rawInitialize(vaultImpl, strategyId);
    }

    function test_FactoryVaultPassesHookGate() public {
        address vault = _createVault(strategyId, curator);
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: int256(1e18), salt: bytes32(0)});

        vm.prank(address(manager));
        bytes4 sel = hook.beforeAddLiquidity(vault, _poolKey(), params, "");
        assertEq(sel, IHooks.beforeAddLiquidity.selector, "factory vault must pass gate");
    }

    function test_NonFactoryAddressRejectedByHookGate() public {
        address attacker = address(0xBAD);
        assertFalse(factory.isVault(attacker));

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: int256(1e18), salt: bytes32(0)});

        vm.prank(address(manager));
        vm.expectRevert(RudderHook.OnlyVault.selector);
        hook.beforeAddLiquidity(attacker, _poolKey(), params, "");
    }

    function test_CreateVault_NonCuratorReverts() public {
        address notCurator = address(0xD00D);
        vm.prank(notCurator);
        vm.expectRevert(VaultFactory.NotCurator.selector);
        factory.createVault(strategyId, _poolKey(), 1000);
    }

    function test_CreateVault_UnknownStrategyReverts() public {
        vm.prank(curator);
        vm.expectRevert(VaultFactory.UnknownStrategy.selector);
        factory.createVault(9999, _poolKey(), 1000);
    }

    function test_CreateVault_HookMismatchReverts() public {
        PoolKey memory k = _poolKey();
        k.hooks = IHooks(address(0xBAD));
        vm.prank(curator);
        vm.expectRevert(VaultFactory.HookMismatch.selector);
        factory.createVault(strategyId, k, 1000);
    }

    function test_CreateVault_UninitializedPoolReverts() public {
        PoolKey memory k = _poolKey();
        k.fee = 500; // a fee/tickSpacing pair that has not been initialized
        k.tickSpacing = 10;
        vm.prank(curator);
        vm.expectRevert(VaultFactory.PoolNotInitialized.selector);
        factory.createVault(strategyId, k, 1000);
    }

    function test_CreateVault_FeeCapClampedToProtocolMax() public {
        vm.prank(curator);
        address vault = factory.createVault(strategyId, _poolKey(), 5000);
        assertEq(RudderVault(vault).feeCapBps(), factory.PROTOCOL_MAX_FEE_BPS(), "fee cap clamped");
    }

    function test_CreateVault_SecondVaultForStrategyReverts() public {
        _createVault(strategyId, curator);
        vm.prank(curator);
        vm.expectRevert(StrategyRegistry.StrategyAlreadyBound.selector);
        factory.createVault(strategyId, _poolKey(), 1000);
    }

    function test_BadConfigRevertsAndRegistersNoVault() public {
        // A factory wired to an implementation whose initialize reverts must fail atomically:
        // no clone is left uninitialized and no vault is registered.
        VaultFactory badFactory = new VaultFactory(
            address(new BadInitVault()), IPoolManager(address(manager)), address(registry), address(hook)
        );

        address predicted =
            Clones.predictDeterministicAddress(badFactory.vaultImplementation(), bytes32(0), address(badFactory));

        vm.prank(curator);
        vm.expectRevert(bytes("bad init"));
        badFactory.createVault(strategyId, _poolKey(), 1000);

        assertEq(badFactory.vaultCount(), 0, "no vault registered after failed init");
        assertFalse(badFactory.isVault(predicted), "predicted clone must not be registered");
        assertEq(badFactory.vaultsLength(), 0, "vault list must stay empty");
    }
}
