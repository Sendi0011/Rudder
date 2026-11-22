// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract WorstCaseBoundTest is RudderIntegrationBase {
    struct TierResult {
        uint256 intervalSeconds;
        uint256 navLossFloorBps;
        uint256 dailyBudgetBps;
        uint256 horizonSeconds;
        uint256 boundBps;
        uint256 observedBps;
        uint256 maxObservedCostBps;
        uint256 rebalances;
    }

    uint256 internal constant DEPOSIT = 100e18;
    uint256 internal constant DEPTH = 100_000e18;
    uint256 internal constant HORIZON = 86_400;
    uint256 internal constant SWAP_AMOUNT = 5e18;
    int24 internal constant CONSERVATIVE_FLOOR = -50;
    uint256 internal constant CONSERVATIVE_INTERVAL = 3600;
    uint256 internal constant CONSERVATIVE_BUDGET_BPS = 200;
    int24 internal constant BALANCED_FLOOR = -100;
    uint256 internal constant BALANCED_INTERVAL = 1800;
    uint256 internal constant BALANCED_BUDGET_BPS = 500;
    int24 internal constant AGGRESSIVE_FLOOR = -200;
    uint256 internal constant AGGRESSIVE_INTERVAL = 600;
    uint256 internal constant AGGRESSIVE_BUDGET_BPS = 1000;

    function test_WorstCaseBoundCoversObservedRebalanceLosses() public {
        TierResult memory conservative =
            _runTier(uint32(CONSERVATIVE_INTERVAL), CONSERVATIVE_FLOOR, uint32(CONSERVATIVE_BUDGET_BPS));
        TierResult memory balanced = _runTier(uint32(BALANCED_INTERVAL), BALANCED_FLOOR, uint32(BALANCED_BUDGET_BPS));
        TierResult memory aggressive =
            _runTier(uint32(AGGRESSIVE_INTERVAL), AGGRESSIVE_FLOOR, uint32(AGGRESSIVE_BUDGET_BPS));

        string memory body = string.concat(
            _tierJson("conservative", conservative),
            ",",
            _tierJson("balanced", balanced),
            ",",
            _tierJson("aggressive", aggressive)
        );
        string memory json = string.concat("{", body, "}");
        if (vm.envOr("WRITE_EVIDENCE", uint256(0)) != 0) {
            vm.writeJson(json, "evidence/worst_case_loss.json");
        }

        assertEq(conservative.navLossFloorBps, 50);
        assertEq(balanced.navLossFloorBps, 100);
        assertEq(aggressive.navLossFloorBps, 200);
        assertEq(conservative.intervalSeconds, 3600);
        assertEq(balanced.intervalSeconds, 1800);
        assertEq(aggressive.intervalSeconds, 600);
        assertEq(conservative.boundBps, 200);
        assertEq(balanced.boundBps, 500);
        assertEq(aggressive.boundBps, 1000);
        assertLt(conservative.boundBps, balanced.boundBps);
        assertLt(balanced.boundBps, aggressive.boundBps);
        assertGt(conservative.rebalances, 0);
        assertGt(balanced.rebalances, 0);
        assertGt(aggressive.rebalances, 0);
    }

    function _runTier(uint32 interval, int24 floorBps, uint32 budgetBps) internal returns (TierResult memory result) {
        Envelope memory env = Envelope({
            maxRangeWidth: 6000,
            maxCenterShift: 3000,
            maxTwapDistanceTicks: 6000,
            minRebalanceInterval: interval,
            maxPriceImpactBps: 10_000,
            maxNavLossBps: floorBps,
            maxDailyNavLossBps: budgetBps
        });
        RudderVault v = _createVault(env);
        _seed(v, alice, -600, 600, DEPOSIT);
        _depthVault(env);
        uint256 ts = _readyOracle(block.timestamp);

        _fundVault(v, bob, 1e18, 1e18);
        vm.prank(bob);
        v.deposit(1e18, 1e18, bob);

        uint256 attempts = HORIZON / interval + 1;
        uint256 observedMicroBps;
        uint256 maxCostMicroBps;
        for (uint256 i = 0; i < attempts; i++) {
            bool zeroForOne = i % 2 == 0;
            _swap(zeroForOne, int256(SWAP_AMOUNT));
            ts = block.timestamp + interval;
            vm.warp(ts);
            int24 lo = zeroForOne ? int24(-1200) : int24(600);
            int24 hi = zeroForOne ? int24(-600) : int24(1200);
            uint256 cost = _tryRebalance(v, lo, hi);
            if (cost > 0) {
                observedMicroBps += cost;
                if (cost > maxCostMicroBps) maxCostMicroBps = cost;
                result.rebalances++;
            }
        }

        result.intervalSeconds = interval;
        result.navLossFloorBps = _abs(floorBps);
        result.dailyBudgetBps = budgetBps;
        result.horizonSeconds = HORIZON;
        result.boundBps = budgetBps;
        result.observedBps = observedMicroBps == 0 ? 0 : (observedMicroBps + 999_999) / 1_000_000;
        result.maxObservedCostBps = maxCostMicroBps == 0 ? 0 : (maxCostMicroBps + 999_999) / 1_000_000;
        assertGt(observedMicroBps, 0);
        assertLe(result.observedBps, result.boundBps);
        assertLe(result.maxObservedCostBps, result.navLossFloorBps);
    }

    function _tryRebalance(RudderVault v, int24 lo, int24 hi) internal returns (uint256 cost) {
        try this._callRebalance(v, lo, hi) returns (uint256 charged) {
            cost = charged;
        } catch {}
    }

    function _callRebalance(RudderVault v, int24 lo, int24 hi) external returns (uint256 cost) {
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

    function _tierJson(string memory name, TierResult memory result) internal pure returns (string memory) {
        string memory head = string.concat(
            "\"",
            name,
            "\":{\"IntervalSeconds\":",
            vm.toString(result.intervalSeconds),
            ",\"NavLossFloorBps\":",
            vm.toString(result.navLossFloorBps)
        );
        string memory middle = string.concat(
            ",\"DailyBudgetBps\":",
            vm.toString(result.dailyBudgetBps),
            ",\"HorizonSeconds\":",
            vm.toString(result.horizonSeconds),
            ",\"BoundBps\":",
            vm.toString(result.boundBps)
        );
        string memory tail = string.concat(
            ",\"ObservedBps\":",
            vm.toString(result.observedBps),
            ",\"MaxObservedCostBps\":",
            vm.toString(result.maxObservedCostBps),
            ",\"Rebalances\":",
            vm.toString(result.rebalances),
            "}"
        );
        return string.concat(head, middle, tail);
    }

    function _createVault(Envelope memory env) internal returns (RudderVault v) {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(env);
        vm.prank(curator);
        v = RudderVault(factory.createVault(id, key, 1000));
    }

    function _seed(RudderVault v, address who, int24 lo, int24 hi, uint256 amount) internal {
        vm.prank(curator);
        v.rebalance(lo, hi);
        token0.mint(who, amount);
        token1.mint(who, amount);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(who);
        v.deposit(amount, amount, who);
    }

    function _depthVault(Envelope memory env) internal {
        RudderVault deep = _createVault(env);
        _seed(deep, address(0x1D0), -600, 600, DEPTH);
    }

    function _readyOracle(uint256 ts) internal returns (uint256) {
        _swap(true, -1);
        ts += 10;
        vm.warp(ts);
        _swap(false, -1);
        ts += 10;
        vm.warp(ts);
        return ts;
    }

    function _fundVault(RudderVault v, address who, uint256 amount0, uint256 amount1) internal {
        token0.mint(who, amount0);
        token1.mint(who, amount1);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
    }

    function _abs(int24 value) internal pure returns (uint256) {
        return value < 0 ? uint256(-int256(value)) : uint256(uint24(value));
    }
}
