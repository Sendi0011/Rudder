// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {MiniSwapRouter} from "./RudderIntegrationBase.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {LiquidityLib} from "../src/libraries/LiquidityLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Drives the vault through randomized deposit/withdraw/swap/rebalance against the real
///         PoolManager. Inputs are derived from current balances, shares and pool state so the
///         actions are expected to succeed and the invariants see post-conditions, not reverts.
contract VaultHandler is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    RudderVault public immutable vault;
    TestERC20 internal immutable t0;
    TestERC20 internal immutable t1;
    MiniSwapRouter internal immutable router;
    PoolKey internal key;
    StrategyRegistry internal immutable registry;
    uint256 internal immutable strategyId;
    address internal curator;
    address[3] internal actors;

    uint256 public ghostDeposits;
    uint256 public ghostWithdrawals;
    uint256 public ghostRebalances;
    uint256 public ghostSwaps;
    uint256 public attemptedDeposits;
    uint256 public attemptedWithdrawals;
    uint256 public attemptedRebalances;
    uint256 public attemptedSwaps;
    uint256 public revertedDeposits;
    uint256 public revertedWithdrawals;
    uint256 public revertedRebalances;
    uint256 public revertedSwaps;
    uint256 public totalCalls;

    constructor(
        RudderVault _vault,
        TestERC20 _t0,
        TestERC20 _t1,
        MiniSwapRouter _router,
        PoolKey memory _key,
        StrategyRegistry _registry,
        uint256 _strategyId,
        address _curator,
        address[3] memory _actors
    ) {
        vault = _vault;
        t0 = _t0;
        t1 = _t1;
        router = _router;
        key = _key;
        registry = _registry;
        strategyId = _strategyId;
        curator = _curator;
        actors = _actors;

        for (uint256 i = 0; i < actors.length; i++) {
            t0.mint(actors[i], 1e30);
            t1.mint(actors[i], 1e30);
            vm.startPrank(actors[i]);
            IERC20(address(t0)).approve(address(vault), type(uint256).max);
            IERC20(address(t1)).approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }

        vm.prank(curator);
        vault.rebalance(-600, 600);
        _deposit(0, 50_000e18, 50_000e18);
        _swap(true, 1e14);
        vm.warp(block.timestamp + 10);
        _swap(false, 1e14);
        vm.warp(block.timestamp + 10);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _tick() internal view returns (int24 tick) {
        (, tick,,) = IPoolManager(router.manager()).getSlot0(key.toId());
    }

    function _swap(bool zeroForOne, uint256 amount) internal {
        int24 lo = vault.tickLower();
        int24 hi = vault.tickUpper();
        uint160 limit = zeroForOne ? TickMath.getSqrtPriceAtTick(lo) : TickMath.getSqrtPriceAtTick(hi);
        router.swap(key, zeroForOne, -int256(amount), limit);
    }

    function _deposit(uint256 seed, uint256 amount0, uint256 amount1) internal {
        address who = _actor(seed);
        vm.prank(who);
        vault.deposit(amount0, amount1, who);
    }

    function deposit(uint256 seed, uint256 amount0, uint256 amount1) public {
        address who = _actor(seed);
        amount0 = bound(amount0, 1e15, 1e18);
        amount1 = amount0;
        t0.mint(who, amount0);
        t1.mint(who, amount1);
        _deposit(seed, amount0, amount1);
        ghostDeposits++;
        totalCalls++;
    }

    function withdraw(uint256 seed, uint256 shares) public {
        address who = _actor(seed);
        uint256 bal = vault.balanceOf(who);
        uint256 half = bal / 2;
        if (half == 0) return;
        shares = bound(shares, 1, half);
        vm.prank(who);
        vault.withdraw(shares, who);
        ghostWithdrawals++;
        totalCalls++;
    }

    function swap(uint256 seed, uint256 amount) public {
        amount = bound(amount, 1e12, 1e14);
        int24 tick = _tick();
        bool zeroForOne = tick > 0 || (tick == 0 && seed % 2 == 0);
        _swap(zeroForOne, amount);
        vm.warp(block.timestamp + 10);
        ghostSwaps++;
        totalCalls++;
    }

    function exercise(uint256 seed, uint256 amount0, uint256 amount1, uint256 shares) external {
        attemptedDeposits++;
        try this.deposit(seed, amount0, amount1) {}
        catch {
            revertedDeposits++;
        }

        attemptedWithdrawals++;
        try this.withdraw(seed, shares) {}
        catch {
            revertedWithdrawals++;
        }

        attemptedSwaps++;
        try this.swap(seed, amount0) {}
        catch {
            revertedSwaps++;
        }

        attemptedDeposits++;
        try this.deposit(seed + 1, amount0 / 2, amount1 / 2) {}
        catch {
            revertedDeposits++;
        }

        attemptedWithdrawals++;
        try this.withdraw(seed + 1, shares) {}
        catch {
            revertedWithdrawals++;
        }

        attemptedRebalances++;
        try this.rebalance(seed) {}
        catch {
            revertedRebalances++;
        }
    }

    uint256 public preNav;
    uint256 public postNav;
    int24 public maxNavLossBps;
    bool public hasRebalanced;

    function rebalance(uint256 seed) public {
        uint32 minInterval = registry.getEnvelope(strategyId).minRebalanceInterval;
        uint256 earliest = vault.lastRebalanceTimestamp() + minInterval;
        if (block.timestamp < earliest) vm.warp(earliest + 1);

        int24 center = (_tick() / 60) * 60;
        int24 halfWidth = seed % 2 == 0 ? int24(600) : int24(300);
        (int24 lo, int24 hi) = (center - halfWidth, center + halfWidth);

        preNav = vault.totalAssetsValue();
        vm.prank(curator);
        vault.rebalance(lo, hi);
        postNav = vault.totalAssetsValue();
        maxNavLossBps = registry.getEnvelope(strategyId).maxNavLossBps;
        hasRebalanced = true;
        ghostRebalances++;
        totalCalls++;
    }
}

/// @notice Stateful invariants: share conservation, protocol fee bound, and the envelope's range
///         width is never exceeded by a live position.
contract VaultInvariantsTest is RudderIntegrationBase {
    VaultHandler internal handler;
    address[3] internal actors;

    function setUp() public override {
        super.setUp();
        actors = [alice, bob, address(0xCA401)];
        handler = new VaultHandler(vault, token0, token1, router, key, registry, strategyId, curator, actors);

        bytes4[] memory sels = new bytes4[](1);
        sels[0] = VaultHandler.exercise.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    function _writeRunEvidence(uint256 attempts, uint256 reverts) internal {
        uint256 runs = vm.envOr("FOUNDRY_INVARIANT_RUNS", uint256(32));
        uint256 depth = vm.envOr("FOUNDRY_INVARIANT_DEPTH", uint256(32));
        console2.log("deposits", handler.ghostDeposits());
        console2.log("withdrawals", handler.ghostWithdrawals());
        console2.log("rebalances", handler.ghostRebalances());
        console2.log("swaps", handler.ghostSwaps());
        console2.log("attempts", attempts);
        console2.log("reverts", reverts);
        string memory obj = "invariant";
        vm.serializeUint(obj, "runs", runs);
        vm.serializeUint(obj, "depth", depth);
        vm.serializeUint(obj, "deposits", handler.ghostDeposits());
        vm.serializeUint(obj, "withdrawals", handler.ghostWithdrawals());
        vm.serializeUint(obj, "rebalances", handler.ghostRebalances());
        vm.serializeUint(obj, "swaps", handler.ghostSwaps());
        vm.serializeUint(obj, "attempts", attempts);
        vm.serializeUint(obj, "reverts", reverts);
        string memory json = vm.serializeUint(obj, "revertRateBps", attempts == 0 ? 0 : (reverts * 10_000) / attempts);
        vm.writeJson(json, "evidence/invariant_runs.json");
    }

    function invariant_ShareConservation() public view {
        uint256 held = vault.balanceOf(actors[0]) + vault.balanceOf(actors[1]) + vault.balanceOf(actors[2])
            + vault.balanceOf(address(vault));
        assertEq(held, vault.totalSupply(), "shares must sum to total supply");
    }

    /// @notice A run must exercise every state-changing path, not just the ones that leave the vault
    ///         untouched. Counters are incremented after the call returns, so they record successes.
    function invariant_ActionsExecuted() public {
        if (handler.totalCalls() == 0) return;
        assertGe(handler.ghostDeposits(), 2, "deposits did not execute");
        assertGe(handler.ghostWithdrawals(), 2, "withdrawals did not execute");
        assertGe(handler.ghostRebalances(), 1, "rebalances did not execute");
        assertGe(handler.ghostSwaps(), 1, "swaps did not execute");
        uint256 attempts = handler.attemptedDeposits() + handler.attemptedWithdrawals() + handler.attemptedRebalances()
            + handler.attemptedSwaps();
        uint256 reverts = handler.revertedDeposits() + handler.revertedWithdrawals() + handler.revertedRebalances()
            + handler.revertedSwaps();
        if (attempts > 0) {
            assertLe((reverts * 10_000) / attempts, 3_000, "handler revert rate too high");
            _writeRunEvidence(attempts, reverts);
        }
    }

    function invariant_FeeCapWithinProtocolMax() public view {
        assertLe(vault.feeCapBps(), vault.PROTOCOL_MAX_FEE_BPS(), "fee cap exceeds protocol max");
    }

    function invariant_EnvelopeWidthRespected() public view {
        if (vault.rangeSet()) {
            Envelope memory env = registry.getEnvelope(strategyId);
            assertLe(vault.tickUpper() - vault.tickLower(), env.maxRangeWidth, "range exceeds envelope");
        }
    }

    /// @notice A rebalance may only lose as much value as the envelope allows: the realized NAV
    ///         cannot fall below the pre-rebalance NAV minus the envelope's loss bound.
    function invariant_RebalanceWithinNavLossBound() public view {
        if (!handler.hasRebalanced()) return;
        uint256 pre = handler.preNav();
        uint256 post = handler.postNav();
        if (pre == 0) return;
        int24 maxLoss = handler.maxNavLossBps();
        uint256 allowedBps = maxLoss < 0 ? uint256(-int256(maxLoss)) : 0;
        uint256 floor = pre - (pre * allowedBps) / 10_000;
        assertGe(post + 1, floor, "rebalance loss exceeds envelope");
    }

    /// @notice Solvency: the vault's real holdings (idle + position, valued at the same TWAP the vault
    ///         uses) must cover what it reports as LP-owned NAV plus the curator's pending fees. In
    ///         other words the vault never promises a redemption it cannot back with tokens.
    function invariant_HoldingsCoverRedemptions() public {
        uint160 sqrtP = vault.twapSqrtPrice();

        uint256 idle0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(vault));
        uint256 idle1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(vault));
        uint256 holdings = LiquidityLib.valueInToken0(idle0, idle1, sqrtP);
        if (vault.positionLiquidity() > 0) {
            (uint256 p0, uint256 p1) = LiquidityLib.getAmountsForLiquidity(
                sqrtP,
                TickMath.getSqrtPriceAtTick(vault.tickLower()),
                TickMath.getSqrtPriceAtTick(vault.tickUpper()),
                vault.positionLiquidity()
            );
            holdings += LiquidityLib.valueInToken0(p0, p1, sqrtP);
        }

        uint256 pending = LiquidityLib.valueInToken0(vault.pendingFees0(), vault.pendingFees1(), sqrtP);
        uint256 nav = vault.totalAssetsValue();
        assertLe(nav + pending, holdings + 1, "nav + pending fees must be backed by holdings");

        assertGe(idle0, vault.pendingFees0(), "pending fee0 not backed by idle tokens");
        assertGe(idle1, vault.pendingFees1(), "pending fee1 not backed by idle tokens");

        uint256 supply = vault.totalSupply();
        if (supply > 0) {
            uint256 sumClaims;
            for (uint256 i = 0; i < actors.length; i++) {
                sumClaims += MathLib.mulDivDown(nav, vault.balanceOf(actors[i]), supply);
            }
            assertLe(sumClaims, nav, "holders cannot collectively redeem more than NAV");
        }
    }
}
