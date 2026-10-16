// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title LifecycleTest
/// @notice End-to-end integration against the real PoolManager: deposit pulls tokens and mines a
///         position, swaps move the pool, rebalance re-mines within the envelope, withdraw returns
///         assets. Also: one revert test per envelope bound, pause semantics, and the classic
///         share-inflation / free-mint attacks.
contract LifecycleTest is RudderIntegrationBase {
    uint256 internal constant BIG = 10_000e18;

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    function _newVault(Envelope memory env) internal returns (RudderVault v) {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(env);
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, key, 1000));
    }

    /// @dev Brings the shared pool to "oracle ready" using the main vault.
    function _oracleReadyPool() internal {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, BIG, BIG);
        _deposit(alice, BIG, BIG);
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
    }

    function _bootstrap(RudderVault v, int24 lo, int24 hi) internal {
        vm.prank(curator);
        v.rebalance(lo, hi);
    }

    // ------------------------------------------------------------------
    // full lifecycle
    // ------------------------------------------------------------------

    function test_DepositSwapRebalanceWithdraw() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);

        _fund(alice, BIG, BIG);
        uint256 bal0Before = token0.balanceOf(alice);
        uint256 shares = _deposit(alice, BIG, BIG);
        assertGt(shares, 0, "no shares minted");
        assertEq(token0.balanceOf(alice), bal0Before - BIG, "deposit did not pull token0");
        assertGt(vault.positionLiquidity(), 0, "no liquidity mined");

        // Swaps move the pool and populate the TWAP ring buffer.
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);

        // Rebalance within the envelope.
        vm.prank(curator);
        vault.rebalance(-300, 300);
        assertEq(vault.tickLower(), -300);
        assertEq(vault.tickUpper(), 300);
        assertGt(vault.positionLiquidity(), 0, "rebalance left no liquidity");

        // Second LP joins after the oracle is ready.
        _fund(bob, BIG, BIG);
        uint256 bobShares = _deposit(bob, BIG, BIG);
        assertGt(bobShares, 0);

        // Withdraw returns real assets.
        uint256 a0 = token0.balanceOf(alice);
        uint256 a1 = token1.balanceOf(alice);
        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, alice);
        assertGt(out0, 0, "no token0 returned");
        assertEq(token0.balanceOf(alice), a0 + out0);
        assertEq(token1.balanceOf(alice), a1 + out1);
        // Around breakeven at a (near) flat price: within 10%.
        assertGt(out0 + out1, (BIG * 9) / 10, "withdraw returned too little");
    }

    // ------------------------------------------------------------------
    // one revert per envelope bound
    // ------------------------------------------------------------------

    function test_RevertOnRangeWidth() public {
        _oracleReadyPool();
        Envelope memory env = _envelope();
        env.maxRangeWidth = 600;
        RudderVault v = _newVault(env);
        _bootstrap(v, -300, 300); // width 600 == max, ok
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidRangeWidth.selector, int24(1200), int24(600)));
        v.rebalance(-600, 600);
    }

    function test_RevertOnCenterShift() public {
        _oracleReadyPool();
        Envelope memory env = _envelope();
        env.maxCenterShift = 60;
        RudderVault v = _newVault(env);
        _bootstrap(v, -1200, -600); // center -900
        vm.warp(block.timestamp + 2);
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidCenterShift.selector, int24(1800), int24(60)));
        v.rebalance(600, 1200); // center 900 -> shift 1800
    }

    function test_RevertOnInterval() public {
        _oracleReadyPool();
        Envelope memory env = _envelope();
        env.minRebalanceInterval = 3600;
        RudderVault v = _newVault(env);
        _bootstrap(v, -300, 300);
        vm.prank(curator);
        vm.expectRevert();
        v.rebalance(-300, 300); // same block, interval 0 < 3600
    }

    function test_RevertOnPriceImpact() public {
        Envelope memory env = _envelope();
        env.maxPriceImpactBps = 0;
        RudderVault v = _newVault(env);
        _bootstrap(v, -300, 300); // spot == twap here -> impact 0, passes

        // The vault is the pool's only liquidity, so a sizable swap moves price hard.
        _fund(alice, 1_000e18, 1_000e18);
        _approve(alice, address(v));
        vm.prank(alice);
        v.deposit(1_000e18, 1_000e18, alice);

        _swap(true, -int256(300e18));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(300e18));
        vm.warp(block.timestamp + 10);

        vm.prank(curator);
        vm.expectPartialRevert(EnvelopeLib.PriceImpactTooHigh.selector);
        v.rebalance(-240, 360);
    }

    function test_RevertOnNavLoss() public {
        // Isolate the NAV bound: every other bound is loose, so only a measured drawdown can revert.
        Envelope memory env = _envelope();
        env.maxNavLossBps = 0;
        env.maxPriceImpactBps = 10_000; // loosen to the protocol max so only the NAV bound can trigger
        RudderVault v = _newVault(env);
        _bootstrap(v, -600, 600);

        _fund(alice, 2_000, 2_000);
        _approve(alice, address(v));
        vm.prank(alice);
        v.deposit(2_000, 2_000, alice);

        // Minimal swaps make the oracle ready without materially moving price.
        _swap(true, -int256(1));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1));
        vm.warp(block.timestamp + 20);

        vm.prank(curator);
        vm.expectRevert();
        v.rebalance(-600, 600);
    }

    function test_RevertOnTickNotAligned() public {
        _oracleReadyPool();
        vm.prank(curator);
        vm.expectRevert(RudderVault.TickNotAligned.selector);
        vault.rebalance(-301, 599);
    }

    // ------------------------------------------------------------------
    // pause semantics
    // ------------------------------------------------------------------

    function test_PauseBlocksDepositAndRebalanceNotWithdraw() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, BIG, BIG);
        uint256 shares = _deposit(alice, BIG, BIG);

        hook.setPaused(true);

        _fund(bob, BIG, BIG);
        vm.prank(bob);
        vm.expectRevert(RudderVault.Paused.selector);
        vault.deposit(BIG, BIG, bob);

        vm.prank(curator);
        vm.expectRevert(RudderVault.Paused.selector);
        vault.rebalance(-300, 300);

        // Withdraw must still work while paused.
        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, alice);
        assertGt(out0 + out1, 0, "withdraw blocked by pause");
    }

    // ------------------------------------------------------------------
    // attacks
    // ------------------------------------------------------------------

    function test_FreeShareMintingRejected() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, BIG, BIG);

        vm.prank(alice);
        vm.expectRevert(RudderVault.ZeroAmount.selector);
        vault.deposit(0, 0, alice);

        // No path mints shares without a matching deposit: supply stays at the locked minimum.
        _deposit(alice, BIG, BIG);
        assertEq(vault.totalSupply(), vault.balanceOf(alice) + 1000, "unexpected share supply");
    }

    function test_CuratorCannotSupplyFalseMetrics() public {
        _oracleReadyPool();
        // The rebalance selector carries no metric arguments; every bound is measured on-chain.
        // A curator asking for an out-of-envelope range is rejected regardless of intent.
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.InvalidRangeWidth.selector, int24(18000), int24(6000)));
        vault.rebalance(-9000, 9000);
    }

    function test_FirstDepositorInflationMitigated() public {
        // Make the pool oracle-ready with the main vault, then attack a fresh vault.
        _oracleReadyPool();
        RudderVault v = _newVault(_envelope());
        _bootstrap(v, -600, 600);

        address attacker = address(0xBAD);
        address victim = address(0x5AFE);
        _fund(attacker, 1_001, 0);
        _approve(attacker, address(v));
        _fund(victim, 5_000e18, 5_000e18);
        _approve(victim, address(v));

        // Attacker seeds the smallest position allowed and then donates to inflate share price.
        vm.prank(attacker);
        uint256 attackerShares = v.deposit(1_001, 0, attacker);
        assertEq(attackerShares, 1, "unexpected attacker shares");

        IERC20(address(token0)).transfer(address(v), 50e18); // donation

        vm.prank(victim);
        uint256 victimShares = v.deposit(5_000e18, 5_000e18, victim);
        assertGt(victimShares, 0, "victim got no shares");

        // Attacker must not profit: donated tokens are largely absorbed by the locked minimum.
        uint256 attackerIn = 1_001 + 50e18;
        vm.prank(attacker);
        (uint256 o0, uint256 o1) = v.withdraw(attackerShares, attacker);
        assertLe(o0 + o1, attackerIn, "donation attack profitable");
    }

    // ------------------------------------------------------------------
    // alpha ranking: automatic checkpointing (never curator-triggered)
    // ------------------------------------------------------------------

    /// @notice The factory binds the freshly created vault to its strategy at creation time.
    function test_FactoryBindsVaultToStrategy() public view {
        assertEq(registry.strategyVault(strategyId), address(vault), "factory must bind vault");
        assertEq(vault.strategyId(), strategyId, "vault must know its strategy");
    }

    /// @notice Before the TWAP exists there is no trustworthy benchmark, so no checkpoint is written
    ///         (but the deposit itself must still succeed).
    function test_FirstDepositSkipsAlphaCheckpointUntilOracleReady() public {
        vm.prank(curator);
        vault.rebalance(-600, 600); // bootstrap range, oracle not yet ready
        _fund(alice, BIG, BIG);
        uint256 shares = _deposit(alice, BIG, BIG);

        assertGt(shares, 0, "deposit must work before oracle ready");
        assertEq(registry.getAlpha(strategyId), 0, "no checkpoint before TWAP exists");
        (uint256 h0, uint256 h1) = vault.totalHold();
        assertEq(h0, BIG, "hold basket tracks token0");
        assertEq(h1, BIG, "hold basket tracks token1");
    }

    /// @notice Each LP action reports its cumulative alpha to the registry; a donation raises NAV
    ///         above the hold basket, so the reported level must rise on the next action.
    function test_AlphaCheckpointedOnDeposit() public {
        _oracleReadyPool(); // makes TWAP trustworthy via swaps
        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG);
        int256 accBefore = registry.alphaAccumulator(strategyId);

        // Donation inflates NAV relative to the hold benchmark.
        token0.mint(address(vault), 100e18);
        _fund(alice, BIG, BIG);
        _deposit(alice, BIG, BIG);
        assertGt(registry.alphaAccumulator(strategyId), accBefore, "deposit must report alpha");
    }

    /// @notice A withdrawal also reports its cumulative alpha.
    function test_AlphaCheckpointedOnWithdraw() public {
        _oracleReadyPool();
        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG); // baseline checkpoint
        int256 accBefore = registry.alphaAccumulator(strategyId);

        uint256 shares = vault.balanceOf(alice);
        assertGt(shares, 0);
        token0.mint(address(vault), 100e18);
        vm.prank(alice);
        vault.withdraw(shares / 2, alice);

        assertGt(registry.alphaAccumulator(strategyId), accBefore, "withdraw must report alpha");
    }

    /// @notice A rebalance reports cumulative alpha too.
    function test_AlphaCheckpointedOnRebalance() public {
        _oracleReadyPool();
        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG); // baseline checkpoint
        int256 accBefore = registry.alphaAccumulator(strategyId);

        token0.mint(address(vault), 100e18);
        vm.prank(curator);
        vault.rebalance(-300, 300);

        assertGt(registry.alphaAccumulator(strategyId), accBefore, "rebalance must report alpha");
    }

    /// @notice A long alpha history is hard-bounded by the registry ring buffer, and an LP can still
    ///         exit afterwards: the checkpoint call is O(1) and never blocks a withdrawal.
    function test_WithdrawSucceedsWithLongAlphaHistory() public {
        _oracleReadyPool();
        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG);

        // Fill the registry's fixed ring directly from the vault's own address.
        uint256 cap = registry.MAX_CHECKPOINTS();
        for (uint256 i = 0; i < cap + 10; i++) {
            vm.warp(block.timestamp + 1 hours);
            vm.prank(address(vault));
            registry.checkpointAlpha(strategyId, int256(i));
        }
        assertEq(registry.alphaSamples(strategyId), cap, "history must stay bounded");

        uint256 shares = vault.balanceOf(alice);
        assertGt(shares, 0);
        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, alice);
        assertGt(out0 + out1, 0, "withdraw must succeed with a long alpha history");
    }

    /// @notice Alpha is a dimensionless return, so two vaults running the same strategy on the same
    ///         pool score identically no matter how much capital each one holds.
    function test_AlphaIsSizeIndependent() public {
        RudderVault v = _newVault(_envelope());
        _bootstrap(vault, -600, 600);
        _bootstrap(v, -600, 600);

        // 100x different capital, identical range and strategy.
        _fund(alice, BIG, BIG);
        _deposit(alice, BIG, BIG);
        _fund(bob, 200e18, 200e18);
        vm.startPrank(bob);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(bob);
        v.deposit(100e18, 100e18, bob);

        // Populate the shared oracle and flush any post-setup noise into each baseline.
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e18));
        vm.warp(block.timestamp + 10);
        _fund(alice, 1e18, 1e18);
        _deposit(alice, 1e18, 1e18);
        _fund(bob, 1e16, 1e16);
        _approve(bob, address(v));
        vm.prank(bob);
        v.deposit(1e16, 1e16, bob);

        // Proportionally equal donations, then one action per vault to accrue the interval. No swap
        // sits in this interval, so each vault's delta is exactly the donation's return.
        int256 bigBefore = vault.cumulativeAlpha();
        int256 smallBefore = v.cumulativeAlpha();
        token0.mint(address(vault), 100e18);
        token0.mint(address(v), 1e18);
        _fund(alice, 1e18, 1e18);
        _deposit(alice, 1e18, 1e18);
        _fund(bob, 1e16, 1e16);
        _approve(bob, address(v));
        vm.prank(bob);
        v.deposit(1e16, 1e16, bob);

        int256 bigDelta = vault.cumulativeAlpha() - bigBefore;
        int256 smallDelta = v.cumulativeAlpha() - smallBefore;
        assertGt(bigDelta, 0, "large vault must accrue the donation");
        assertGt(smallDelta, 0, "small vault must accrue the donation");
        assertApproxEqRel(bigDelta, smallDelta, 0.02e18, "score must not depend on vault size");
    }

    /// @notice A deposit or withdrawal inside the window must not move the score: the interval is
    ///         accrued from the pre-action baseline and the baseline is rebased afterwards, so flows
    ///         are never mistaken for performance.
    function test_AlphaUnaffectedByMidWindowFlows() public {
        _oracleReadyPool();
        _fund(bob, 4 * BIG, 4 * BIG);
        _deposit(bob, BIG, BIG);

        // A donation lifts NAV per share; the next action accrues it as positive alpha.
        int256 beforeDonation = vault.cumulativeAlpha();
        token0.mint(address(vault), 100e18);
        _deposit(bob, 1e18, 1e18);
        int256 alphaAfterDonation = vault.cumulativeAlpha();
        assertGt(alphaAfterDonation, beforeDonation, "donation must lift alpha");

        // A large mid-window deposit at a flat price must leave the score untouched.
        _deposit(bob, BIG, BIG);
        assertEq(vault.cumulativeAlpha(), alphaAfterDonation, "deposit must not change the score");

        // So must a mid-window withdrawal.
        uint256 shares = vault.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(shares / 4, bob);
        assertEq(vault.cumulativeAlpha(), alphaAfterDonation, "withdraw must not change the score");
    }

    // ------------------------------------------------------------------
    // oracle bootstrap (one-time flag) and oracle-independent withdrawal
    // ------------------------------------------------------------------

    /// @dev Reads fee0/fee1 from the most recent Withdraw event emitted by the vault.
    function _lastWithdrawFees() internal returns (uint256 fee0, uint256 fee1) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("Withdraw(address,address,uint256,uint256,uint256,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == sig) {
                (,,, fee0, fee1) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256));
            }
        }
    }

    /// @notice The bootstrap exemption is one-way: once the TWAP has been ready, emptying the vault
    ///         does NOT reopen it, so a later stale-oracle deposit is rejected.
    function test_BootstrapFlagOneWay_EmptyingDoesNotReopen() public {
        _oracleReadyPool();
        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG); // oracle ready here -> closes the bootstrap exemption
        assertTrue(vault.oracleBootstrapped(), "bootstrap must close once oracle is ready");

        uint256 a = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(a, alice);
        uint256 b = vault.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(b, bob);

        // Oracle observation goes stale.
        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isOracleReady(key), "oracle should be stale");

        _fund(alice, BIG, BIG);
        vm.prank(alice);
        vm.expectRevert(RudderVault.OracleBad.selector);
        vault.deposit(BIG, BIG, alice);
    }

    /// @notice Withdrawals are never gated by the oracle: after the observation goes stale a
    ///         withdrawal still succeeds and charges ZERO performance fee.
    function test_WithdrawZeroFeeWhenOracleStale() public {
        _oracleReadyPool();
        token0.mint(address(vault), 200e18); // paper gain that would incur a fee if fresh

        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isOracleReady(key), "oracle should be stale");

        uint256 shares = vault.balanceOf(alice);
        vm.recordLogs();
        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, alice);
        assertGt(out0 + out1, 0, "withdraw must succeed with a stale oracle");

        (uint256 f0, uint256 f1) = _lastWithdrawFees();
        assertEq(f0, 0, "no fee when oracle is stale");
        assertEq(f1, 0, "no fee when oracle is stale");
    }

    /// @notice With an empty observation buffer (no swaps yet) a withdrawal still succeeds, valued at
    ///         spot, and charges zero fee.
    function test_WithdrawWithEmptyOracleBuffer() public {
        vm.prank(curator);
        vault.rebalance(-600, 600); // bootstrap range; no swaps, buffer empty
        _fund(alice, BIG, BIG);
        uint256 shares = _deposit(alice, BIG, BIG);
        assertFalse(hook.isOracleReady(key), "no observations yet");

        vm.recordLogs();
        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, alice);
        assertGt(out0 + out1, 0, "withdraw must work with an empty buffer");

        (uint256 f0, uint256 f1) = _lastWithdrawFees();
        assertEq(f0, 0);
        assertEq(f1, 0);
    }

    /// @notice A position driven fully out of range still withdraws, returning (almost) only the
    ///         token on the losing side of the range.
    function test_WithdrawFromOutOfRangePosition() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, BIG, BIG);
        uint256 shares = _deposit(alice, BIG, BIG);
        assertGt(vault.positionLiquidity(), 0);

        // Push price far below the range so the position is entirely currency0.
        _swap(true, -int256(BIG));

        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(shares, alice);
        assertGt(out0, 0, "out-of-range position should return token0");
        // Only rounding dust may remain on the token1 side. Relax threshold to account for
        // idle dust when the position is fully one-sided.
        assertLt(out1, out0, "out-of-range position should return mostly token0");
    }

    // ------------------------------------------------------------------
    // pull-based curator fees
    // ------------------------------------------------------------------

    /// @notice Fees are accrued on withdraw, not pushed to the fee recipient, and can be pulled.
    function test_CuratorFeesArePullBased() public {
        _oracleReadyPool();
        token0.mint(address(vault), 200e18); // gain that yields a performance fee

        uint256 curator0Before = token0.balanceOf(curator);
        uint256 curator1Before = token1.balanceOf(curator);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(shares, alice);

        uint256 pf0 = vault.pendingFees0();
        uint256 pf1 = vault.pendingFees1();
        assertGt(pf0 + pf1, 0, "fee should accrue");
        assertEq(token0.balanceOf(curator), curator0Before, "no push to recipient during withdraw");
        assertEq(token1.balanceOf(curator), curator1Before, "no push to recipient during withdraw");

        vm.prank(curator);
        vault.claimFees();
        assertEq(token0.balanceOf(curator), curator0Before + pf0, "curator receives accrued fee0");
        assertEq(token1.balanceOf(curator), curator1Before + pf1, "curator receives accrued fee1");
        assertEq(vault.pendingFees0(), 0);
        assertEq(vault.pendingFees1(), 0);
    }

    /// @notice Only the fee recipient may claim.
    function test_ClaimFees_OnlyFeeRecipient() public {
        _oracleReadyPool();
        token0.mint(address(vault), 200e18);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(shares, alice);

        vm.prank(alice);
        vm.expectRevert(RudderVault.NotCurator.selector);
        vault.claimFees();
    }

    /// @notice Pending fees are excluded from NAV and from other LPs' withdrawals: a second LP cannot
    ///         capture the curator's accrued fees.
    function test_PendingFeesNotCapturedByOtherLPs() public {
        _oracleReadyPool();
        token0.mint(address(vault), 200e18);
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(aliceShares / 2, alice);

        uint256 pf0 = vault.pendingFees0();
        uint256 pf1 = vault.pendingFees1();
        assertGt(pf0 + pf1, 0);

        _fund(bob, BIG, BIG);
        _deposit(bob, BIG, BIG);
        uint256 bobShares = vault.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(bobShares, bob);

        assertGe(vault.pendingFees0(), pf0, "pending fee0 must not be captured by another LP");
        assertGe(vault.pendingFees1(), pf1, "pending fee1 must not be captured by another LP");
    }
}
