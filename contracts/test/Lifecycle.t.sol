// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
        env.maxPriceImpactBps = type(uint32).max;
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
}
