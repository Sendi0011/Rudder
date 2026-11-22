// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

using stdStorage for StdStorage;

contract DailyBudgetTest is RudderIntegrationBase {
    uint256 internal constant DEPOSIT = 100e18;
    uint256 internal constant DEPTH = 100_000e18;

    function _env(uint32 budgetBps, int24 floorBps, uint32 interval) internal pure returns (Envelope memory) {
        return Envelope({
            maxRangeWidth: 6000,
            maxCenterShift: 6000,
            maxTwapDistanceTicks: 6000,
            minRebalanceInterval: interval,
            maxPriceImpactBps: 10_000,
            maxNavLossBps: floorBps,
            maxDailyNavLossBps: budgetBps
        });
    }

    function _setup(Envelope memory env) internal returns (RudderVault v, uint256 vaultStrategyId) {
        vm.prank(curator);
        vaultStrategyId = registry.registerStrategy(env);
        vm.prank(curator);
        v = RudderVault(factory.createVault(vaultStrategyId, key, 1000));
        vm.prank(curator);
        v.rebalance(-600, 600);
        token0.mint(alice, DEPOSIT);
        token1.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(alice);
        v.deposit(DEPOSIT, DEPOSIT, alice);

        (RudderVault deep,) = _createDeep(env);
        _seedDeep(deep);
        _advance(env.minRebalanceInterval);
    }

    function _createDeep(Envelope memory env) internal returns (RudderVault deep, uint256 id) {
        vm.prank(curator);
        id = registry.registerStrategy(env);
        vm.prank(curator);
        deep = RudderVault(factory.createVault(id, key, 1000));
    }

    function _seedDeep(RudderVault deep) internal {
        vm.prank(curator);
        deep.rebalance(-600, 600);
        token0.mint(address(0x1D0), DEPTH);
        token1.mint(address(0x1D0), DEPTH);
        vm.startPrank(address(0x1D0));
        IERC20(address(token0)).approve(address(deep), type(uint256).max);
        IERC20(address(token1)).approve(address(deep), type(uint256).max);
        vm.stopPrank();
        vm.prank(address(0x1D0));
        deep.deposit(DEPTH, DEPTH, address(0x1D0));
    }

    function _advance(uint32 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
        _swap(true, -1);
    }

    function _seedBucket(RudderVault v, uint256 bucket) internal {
        stdstore.target(address(v)).sig("lossBucket()").checked_write(bucket);
        stdstore.target(address(v)).sig("lastBucketUpdate()").checked_write(block.timestamp);
        assertEq(v.lossBucket(), bucket);
        assertEq(v.lastBucketUpdate(), block.timestamp);
    }

    function _step(RudderVault v, bool zeroForOne) public returns (uint256 cost) {
        int24 lo = zeroForOne ? int24(-6000) : int24(0);
        int24 hi = zeroForOne ? int24(0) : int24(6000);
        vm.recordLogs();
        vm.prank(curator);
        v.rebalance(lo, hi);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("LossBucketUpdated(uint256,uint256,uint256)")) {
                (cost,) = abi.decode(logs[i].data, (uint256, uint256));
                return cost;
            }
        }
    }

    function _spend(RudderVault v, uint32 interval, bool zeroForOne) internal returns (uint256 cost, uint256 ts) {
        _advance(interval + 1);
        cost = this._step(v, zeroForOne);
        ts = block.timestamp;
    }

    function test_ExhaustedBucketBlocksWithSpecificError() public {
        (RudderVault v,) = _setup(_env(40, -20, 10));
        uint256 capacity = (40 * 1_000_000) / 2;
        uint256 seeded = capacity - 100_000;
        _seedBucket(v, seeded);
        _advance(11);
        vm.expectPartialRevert(RudderVault.DailyNavLossBudgetExceeded.selector);
        this._step(v, true);
        assertEq(v.lossBucket(), seeded);
    }

    function test_BucketRefillsAndAllowsRebalance() public {
        (RudderVault v,) = _setup(_env(40, -20, 10));
        uint256 capacity = (40 * 1_000_000) / 2;
        _seedBucket(v, capacity - 100_000);
        _advance(11);
        vm.expectPartialRevert(RudderVault.DailyNavLossBudgetExceeded.selector);
        this._step(v, true);

        (uint256 cost,) = _spend(v, 86_400, true);
        assertGt(cost, 0);
        assertEq(v.lossBucket(), cost);
        assertLe(v.lossBucket(), capacity);
    }

    function test_DayBoundaryCannotExceedRollingBudget() public {
        (RudderVault v,) = _setup(_env(100, -50, 10));
        uint256 capacity = (100 * 1_000_000) / 2;
        uint256 budget = 100 * 1_000_000;
        _seedBucket(v, 100_000);

        (uint256 cost0, uint256 ts0) = _spend(v, 10, true);
        (uint256 cost1, uint256 ts1) = _spend(v, 86_410, false);
        assertGt(ts1 - ts0, 86_400);
        assertGt(cost0, 0);
        assertGt(cost1, 0);
        assertLe(cost0, budget);
        assertLe(cost1, budget);
        assertLe(v.lossBucket(), capacity);
    }

    function test_TighteningBlocksAboveCapacityAndLoosenWaitsTimelock() public {
        Envelope memory loose = _env(1000, -500, 10);
        (RudderVault v, uint256 id) = _setup(loose);
        uint256 seeded = (1000 * 1_000_000) / 2 - 10_000;
        _seedBucket(v, seeded);

        Envelope memory tight = _env(40, -20, 10);
        vm.prank(curator);
        registry.tightenEnvelope(id, tight);
        _advance(11);
        vm.expectPartialRevert(RudderVault.DailyNavLossBudgetExceeded.selector);
        this._step(v, true);

        vm.prank(curator);
        registry.queueLoosenEnvelope(id, loose);
        vm.expectRevert(StrategyRegistry.TimelockNotReady.selector);
        vm.prank(curator);
        registry.applyLoosenEnvelope(id);

        _advance(uint32(registry.LOOSEN_DELAY()));
        vm.prank(curator);
        registry.applyLoosenEnvelope(id);
        (, Envelope memory applied,) = registry.strategies(id);
        assertEq(applied.maxDailyNavLossBps, 1000);
        (uint256 cost,) = _spend(v, 10, true);
        assertEq(v.lossBucket(), cost);
    }

    function test_ExitsAndPokesIgnoreBucket() public {
        (RudderVault v,) = _setup(_env(40, -20, 10));
        uint256 capacity = (40 * 1_000_000) / 2;
        uint256 seeded = capacity - 100_000;
        _seedBucket(v, seeded);

        token0.mint(bob, DEPOSIT);
        token1.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        uint256 bobShares = v.deposit(DEPOSIT, DEPOSIT, bob);
        vm.stopPrank();
        assertGt(bobShares, 0);
        assertEq(v.lossBucket(), seeded);

        uint256 aliceShares = v.balanceOf(alice);
        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = v.withdraw(aliceShares / 2, alice);
        assertGt(amount0 + amount1, 0);
        assertEq(v.balanceOf(alice), aliceShares - aliceShares / 2);
        assertEq(v.lossBucket(), seeded);

        vm.prank(curator);
        v.pokeAlpha();
        assertEq(v.lossBucket(), seeded);
    }

    function test_ValidateRejectsInvalidDailyBudget() public {
        vm.expectRevert(EnvelopeLib.ZeroDailyNavLossBudget.selector);
        vm.prank(curator);
        registry.registerStrategy(_env(0, 0, 10));

        vm.expectRevert(abi.encodeWithSelector(EnvelopeLib.DailyNavLossBudgetTooHigh.selector, 1001, 1000));
        vm.prank(curator);
        registry.registerStrategy(_env(1001, -500, 10));

        vm.expectRevert(
            abi.encodeWithSelector(EnvelopeLib.NavLossFloorExceedsBudget.selector, int24(-100), uint32(100))
        );
        vm.prank(curator);
        registry.registerStrategy(_env(100, -100, 10));
    }

    function test_IsTighterTreatsSmallerBudgetAsTighter() public pure {
        Envelope memory loose = _env(1000, -500, 10);
        Envelope memory tight = _env(500, -250, 10);
        assertTrue(EnvelopeLib.isTighter(loose, tight));
        assertFalse(EnvelopeLib.isTighter(tight, loose));
    }
}
