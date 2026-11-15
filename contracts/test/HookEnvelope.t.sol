// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title HookEnvelopeTest
/// @notice The hook independently enforces the strategy envelope on every vault liquidity add, so a
///         vault that skips its own checks still cannot seat liquidity outside the envelope. The
///         gate is unit-tested directly and also exercised end-to-end through `PoolManager.unlock`.
contract HookEnvelopeTest is RudderIntegrationBase {
    uint256 internal constant BIG = 10_000e18;
    uint8 internal constant ACTION_ADD = 1;

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

    function _deposit(RudderVault v, address who, uint256 amount) internal {
        vm.prank(who);
        v.deposit(amount, amount, who);
    }

    function _readyPool() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
    }

    /// @dev Prime a vault: bootstrap range, deposit, then make the oracle live.
    function _prime(Envelope memory env) internal returns (RudderVault v) {
        v = _newVault(env);
        vm.prank(curator);
        v.rebalance(-300, 300);
        _fundVault(v, alice, BIG, BIG);
        _deposit(v, alice, BIG);
        _readyPool();
    }

    /// @dev Call the hook's add gate directly, as the PoolManager would.
    function _hookAdd(RudderVault v, int24 lo, int24 hi) internal {
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: lo, tickUpper: hi, liquidityDelta: 1e15, salt: bytes32(0)});
        vm.prank(address(manager));
        hook.beforeAddLiquidity(address(v), key, params, "");
    }

    /// @dev Drive the vault's low-level add path with caller-chosen ticks, skipping `rebalance`.
    function _rawAdd(RudderVault v, int24 lo, int24 hi) internal {
        vm.prank(address(v));
        manager.unlock(abi.encode(ACTION_ADD, lo, hi, uint128(1e15), address(v)));
    }

    // ------------------------------------------------------------------
    // the hook, not the vault, is the backstop
    // ------------------------------------------------------------------

    function test_HookRejectsWideRangeFromBuggyVault() public {
        RudderVault v = _prime(_envelope());

        vm.expectPartialRevert(EnvelopeLib.InvalidRangeWidth.selector);
        _hookAdd(v, -6000, 6000);
    }

    function test_HookRejectsMisalignedRangeFromBuggyVault() public {
        RudderVault v = _prime(_envelope());

        vm.expectPartialRevert(RudderHook.RangeNotAligned.selector);
        _hookAdd(v, -599, 300);
    }

    function test_HookRejectsRangeTooFarFromTwapFromBuggyVault() public {
        Envelope memory env = _envelope();
        env.maxTwapDistanceTicks = 100;
        RudderVault v = _prime(env);

        vm.expectPartialRevert(EnvelopeLib.InvalidParams.selector);
        _hookAdd(v, 1200, 1800);
    }

    function test_HookRejectsRangeChangeBeforeInterval() public {
        Envelope memory env = _envelope();
        env.minRebalanceInterval = 1000;
        RudderVault v = _prime(env);

        // The deposit set the tracked range; a range change now is inside the interval.
        vm.expectPartialRevert(EnvelopeLib.IntervalTooShort.selector);
        _hookAdd(v, -120, 120);
    }

    function test_HookAllowsTopUpInSameRange() public {
        Envelope memory env = _envelope();
        env.minRebalanceInterval = 1000;
        RudderVault v = _prime(env);

        _fundVault(v, bob, BIG, BIG);
        _deposit(v, bob, BIG); // same range, same block: a top-up, not a range change
        assertGt(v.balanceOf(bob), 0, "top-up should not be gated");
    }

    /// @notice End-to-end: a crafted add that bypasses the vault's own range checks still reverts at
    ///         the hook, and the vault's live position is untouched.
    function test_BuggyVaultCannotSeatLiquidityOutsideEnvelope() public {
        RudderVault v = _prime(_envelope());
        uint128 before = v.positionLiquidity();
        assertGt(before, 0);

        vm.expectRevert();
        _rawAdd(v, -6000, 6000);

        assertEq(v.positionLiquidity(), before, "hook must block the out-of-envelope add");
    }

    // ------------------------------------------------------------------
    // withdrawals are never gated
    // ------------------------------------------------------------------

    function test_WithdrawUnaffectedByHookGate() public {
        RudderVault v = _prime(_envelope());

        vm.prank(curator);
        v.rebalance(-600, 600);

        uint256 shares = v.balanceOf(alice);
        uint256 a0 = token0.balanceOf(alice);
        uint256 a1 = token1.balanceOf(alice);
        vm.prank(alice);
        (uint256 out0, uint256 out1) = v.withdraw(shares, alice);

        assertGt(out0 + out1, 0, "withdraw returned nothing");
        assertEq(token0.balanceOf(alice), a0 + out0);
        assertEq(token1.balanceOf(alice), a1 + out1);
    }

    // ------------------------------------------------------------------
    // cost is bounded
    // ------------------------------------------------------------------

    function test_HookGateGasBoundedAcrossObservations() public {
        RudderVault v = _prime(_envelope());

        uint256 low = _depositGas(v);
        for (uint256 i = 0; i < 100; i++) {
            _swap(true, -int256(1e6));
            vm.warp(block.timestamp + 1);
        }
        uint256 high = _depositGas(v);

        assertLt(high, low + 100_000, "add-liquidity gas grew with observation count");
    }

    function _depositGas(RudderVault v) internal returns (uint256 used) {
        _fundVault(v, bob, 1e18, 1e18);
        uint256 g = gasleft();
        vm.prank(bob);
        v.deposit(1e18, 1e18, bob);
        used = g - gasleft();
    }
}
