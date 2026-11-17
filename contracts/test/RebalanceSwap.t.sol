// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title RebalanceSwapTest
/// @notice The rebalance path balances idle before re-mining by swapping the excess side through the
///         real PoolManager. A second vault supplies depth so those swaps trade against real
///         liquidity instead of a temporarily empty pool. The swap is bounded by the tighter of the
///         envelope and the protocol price-impact ceiling, and the whole rebalance is re-checked for
///         price impact and NAV loss on-chain.
contract RebalanceSwapTest is RudderIntegrationBase {
    uint256 internal constant SHALLOW = 100e18;
    uint256 internal constant DEEP = 100_000e18;
    address internal lp = address(0x1D0);

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    function _newVault(Envelope memory env) internal returns (RudderVault v) {
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

    function _depositInto(RudderVault v, address who, uint256 amount) internal {
        vm.prank(who);
        v.deposit(amount, amount, who);
    }

    /// @dev Second vault that provides passive depth in the shared pool. Its position is never
    ///      removed during the tested vault's rebalance, so swaps actually convert tokens.
    function _depthVault(uint256 amount) internal returns (RudderVault deep) {
        deep = _newVault(_envelope());
        vm.prank(curator);
        deep.rebalance(-3000, 3000);
        _fundVault(deep, lp, amount, amount);
        _depositInto(deep, lp, amount);
    }

    function _readyPool() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
    }

    /// @dev Main vault seated in a wide, price-straddling range so it holds both tokens, plus a
    ///      depth vault of `depth` tokens per side. Returns the main vault.
    function _prime(Envelope memory env, uint256 dep, uint256 depth) internal returns (RudderVault v) {
        v = _newVault(env);
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        _fundVault(v, alice, dep, dep);
        _depositInto(v, alice, dep);
        if (depth > 0) _depthVault(depth);
        _readyPool();
    }

    /// @dev Seeds a vault and makes the oracle ready without moving spot away from tick 0.
    function _primeWithTinySamples(Envelope memory env) internal returns (RudderVault v) {
        v = _newVault(env);
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        _fundVault(v, alice, SHALLOW, SHALLOW);
        _depositInto(v, alice, SHALLOW);
        _swap(true, -int256(1));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1));
        vm.warp(block.timestamp + 10);
    }

    // ------------------------------------------------------------------
    // swap direction: the excess side is swapped out, the needed side is bought
    // ------------------------------------------------------------------

    /// @notice Range fully above the price needs only token0, so the vault sells token1 and the
    ///         spot moves up.
    function test_RebalanceAbovePriceSellsToken1() public {
        RudderVault v = _prime(_envelope(), SHALLOW, DEEP);
        uint160 before = _sqrtPrice();

        vm.prank(curator);
        v.rebalance(600, 1200);

        assertGt(_sqrtPrice(), before, "swap should have bought token0");
        assertGt(v.positionLiquidity(), 0, "no liquidity mined after swap");
        assertEq(v.tickLower(), 600);
        assertEq(v.tickUpper(), 1200);
    }

    /// @notice Range fully below the price needs only token1, so the vault sells token0 and the
    ///         spot moves down.
    function test_RebalanceBelowPriceSellsToken0() public {
        RudderVault v = _prime(_envelope(), SHALLOW, DEEP);
        uint160 before = _sqrtPrice();

        vm.prank(curator);
        v.rebalance(-1200, -600);

        assertLt(_sqrtPrice(), before, "swap should have sold token0");
        assertGt(v.positionLiquidity(), 0, "no liquidity mined after swap");
        assertEq(v.tickLower(), -1200);
        assertEq(v.tickUpper(), -600);
    }

    /// @notice An in-range range whose ratio already matches the idle mix should not trade: the
    ///         balanced branch leaves the spot untouched and re-mines with both tokens.
    function test_RebalanceInRangeDoesNotSwapWhenBalanced() public {
        RudderVault v = _prime(_envelope(), SHALLOW, DEEP);
        uint160 before = _sqrtPrice();

        vm.prank(curator);
        v.rebalance(-600, 600);

        uint256 diff = before > _sqrtPrice() ? before - _sqrtPrice() : _sqrtPrice() - before;
        assertLe(diff, uint256(before) / 200, "balanced rebalance should not move spot");
        assertGt(v.positionLiquidity(), 0);
    }

    /// @notice A large excess cannot be fully swapped within the impact cap; the swap stops at the
    ///         limit, the rebalance still succeeds, and the unswapped side is left idle.
    function test_RebalanceStopsAtPriceLimitAndLeavesResidual() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 10;
        RudderVault v = _prime(env, 1000e18, 10e18);
        uint160 before = _sqrtPrice();

        vm.prank(curator);
        v.rebalance(600, 1200);

        uint160 afterP = _sqrtPrice();
        uint256 moved = afterP > before ? afterP - before : before - afterP;
        assertLe(moved, uint256(before) / 500 + 1, "swap moved past the price-impact limit");
        assertGt(token1.balanceOf(address(v)), 1e18, "limit should have left token1 idle");
    }

    // ------------------------------------------------------------------
    // envelope bounds are still enforced after the swap
    // ------------------------------------------------------------------

    /// @notice The swap fee is a real loss against the TWAP-valued NAV; an envelope that allows none
    ///         must reject the rebalance.
    function test_RebalanceRevertsOnNavLossBeyondEnvelope() public {
        Envelope memory env = _envelope();
        env.maxNavLossBps = 0;
        RudderVault v = _prime(env, 1000e18, DEEP);

        vm.prank(curator);
        vm.expectPartialRevert(EnvelopeLib.NavLossTooLarge.selector);
        v.rebalance(600, 1200);
    }

    /// @notice With no idle there is nothing to swap, and rebalancing must still succeed.
    function test_RebalanceWithZeroIdleSkipsSwap() public {
        RudderVault v = _newVault(_envelope());
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        uint160 before = _sqrtPrice();
        vm.warp(block.timestamp + 100);

        vm.prank(curator);
        v.rebalance(-600, 600);

        assertEq(_sqrtPrice(), before, "zero idle must not move the price");
        assertEq(v.positionLiquidity(), 0);
    }

    /// @notice The curator cannot widen the realized impact past the envelope: a spot already beyond
    ///         it makes the rebalance revert before any swap is attempted.
    function test_RebalanceCannotExceedEnvelopeImpact() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 50;
        RudderVault v = _prime(env, 1000e18, 10e18);

        _swap(true, -int256(50e18));

        vm.prank(curator);
        vm.expectPartialRevert(EnvelopeLib.PriceImpactTooHigh.selector);
        v.rebalance(300, 600);
    }

    /// @notice A zero impact cap forbids any rebalance swap: the limit and the post-swap check agree.
    function test_ZeroImpactCapSkipsSwap() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 0;
        RudderVault v = _primeWithTinySamples(env);

        uint160 before = _sqrtPrice();
        uint256 idle0Before = token0.balanceOf(address(v));
        vm.prank(curator);
        v.rebalance(600, 1200);

        assertEq(_sqrtPrice(), before, "zero cap must not move spot");
        assertEq(token0.balanceOf(address(v)), idle0Before, "zero cap must leave the excess side idle");
        assertEq(v.tickLower(), 600);
        assertEq(v.tickUpper(), 1200);
    }

    /// @notice A spot already away from the TWAP is rejected before any swap when the cap is zero.
    function test_ZeroImpactCapRejectsDeviatedSpot() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 0;
        RudderVault v = _primeWithTinySamples(env);

        _swap(true, -int256(50e18));

        vm.prank(curator);
        vm.expectPartialRevert(EnvelopeLib.PriceImpactTooHigh.selector);
        v.rebalance(600, 1200);
    }

    /// @notice The realized NAV after a rebalance is never below the pre-rebalance NAV minus the
    ///         envelope's loss allowance.
    function test_RebalancePreservesNavWithinLossBound() public {
        Envelope memory env = _envelope();
        env.maxNavLossBps = -100; // 1% allowance
        RudderVault v = _prime(env, SHALLOW, DEEP);

        uint256 pre = v.totalAssetsValue();
        vm.prank(curator);
        v.rebalance(600, 1200);
        uint256 post = v.totalAssetsValue();

        assertGe(post + 1, pre - (pre * 100) / 10_000, "post-rebalance NAV broke the loss bound");
    }
}
