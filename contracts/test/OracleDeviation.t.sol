// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Regression tests for the oracle hardening: pre-swap sampling (same-block manipulation is
///         ignored), the deposit spot-vs-TWAP deviation guard, and the range-distance-from-TWAP bound.
contract OracleDeviationTest is RudderIntegrationBase {
    uint256 internal constant BIG = 1e18;

    function _newVaultTight(Envelope memory env) internal returns (RudderVault v) {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(env);
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, key, 1000));
    }

    function _fundVault(RudderVault v, address who, uint256 amount0, uint256 amount1) internal {
        token0.mint(who, amount0);
        token1.mint(who, amount1);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Records two observations with negligible price impact, so the oracle is ready without
    ///      collapsing the (small) pool toward its price limit.
    function _readyPool() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
    }

    /// @notice A manipulator cannot choose the price at which it is sampled: the sample is the
    ///         pre-swap price and only the first swap of a block is recorded.
    function test_SameBlockPushDoesNotMoveTwap() public {
        vm.prank(curator);
        vault.rebalance(-3000, 3000); // wide range so a test swap stays inside it
        _fund(alice, BIG, BIG);
        _deposit(alice, BIG, BIG);
        _readyPool();
        assertTrue(hook.isOracleReady(key), "oracle must be ready");

        uint160 honest = _sqrtPrice();

        // First swap of a new block records the honest pre-swap price...
        _swap(true, -int256(3e16));
        uint160 manipulated = _sqrtPrice();
        assertTrue(manipulated < honest, "swap must move spot");

        // ...and a second swap in the same block must not overwrite that sample.
        _swap(false, -int256(3e16));
        vm.warp(block.timestamp + 1);

        uint160 twap = hook.consult(key, 1);
        uint256 diff = twap > honest ? uint256(twap - honest) : uint256(honest - twap);
        assertLe(diff, uint256(honest) / 1000, "same-block push leaked into the TWAP");
    }

    /// @notice Once the oracle is live, a deposit priced off a manipulated spot is rejected.
    function test_DepositRejectedWhenSpotDeviatesFromTwap() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 500; // 5%
        RudderVault tight = _newVaultTight(env);

        vm.prank(curator);
        tight.rebalance(-3000, 3000); // wide range so a test swap stays inside it
        _fundVault(tight, bob, BIG, BIG);
        vm.prank(bob);
        tight.deposit(BIG, BIG, bob);

        _readyPool();
        assertTrue(hook.isOracleReady(key), "oracle must be ready");

        // Shove the spot beyond the 5% deviation bound in the current block (still inside the range).
        _swap(true, -int256(8e17));
        assertGt(hook.consult(key, 1), 0);

        _fundVault(tight, alice, BIG, BIG);
        vm.prank(alice);
        vm.expectRevert(RudderVault.SpotTwapDeviation.selector);
        tight.deposit(BIG, BIG, alice);
    }

    /// @notice The range centre may not be pushed further from the TWAP tick than the envelope allows.
    function test_RebalanceRejectedWhenCenterTooFarFromTwap() public {
        Envelope memory env = _envelope();
        env.maxTwapDistanceTicks = 100;
        RudderVault tight = _newVaultTight(env);

        // Bootstrap at the initial tick so the distance is zero, then seed liquidity.
        vm.prank(curator);
        tight.rebalance(-300, 300);
        _fundVault(tight, bob, BIG, BIG);
        vm.prank(bob);
        tight.deposit(BIG, BIG, bob);

        _readyPool();
        assertTrue(hook.isOracleReady(key), "oracle must be ready");
        vm.warp(block.timestamp + 2);

        vm.prank(curator);
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        tight.rebalance(600, 1200); // center 900, far beyond the 100-tick bound
    }
}
