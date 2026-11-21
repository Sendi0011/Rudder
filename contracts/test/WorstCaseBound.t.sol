// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract WorstCaseBoundTest is RudderIntegrationBase {
    uint256 internal constant DEPOSIT = 100e18;
    uint256 internal constant DEPTH = 100_000e18;
    uint256 internal constant LOSS_CAP_BPS = 500;
    uint256 internal constant INTERVAL = 10;
    uint256 internal constant CHARGED_REBALANCES = 3;

    function test_WorstCaseBoundCoversObservedRebalanceLosses() public {
        Envelope memory env = Envelope({
            maxRangeWidth: 6000,
            maxCenterShift: 3000,
            maxTwapDistanceTicks: 6000,
            minRebalanceInterval: uint32(INTERVAL),
            maxPriceImpactBps: 10_000,
            maxNavLossBps: -500
        });
        RudderVault v = _createVault(env);
        _seed(v, alice, -600, 600, DEPOSIT);
        _depthVault(env);
        uint256 ts = _readyOracle(block.timestamp);

        _fundVault(v, bob, 1e18, 1e18);
        vm.prank(bob);
        v.deposit(1e18, 1e18, bob);

        uint256 bootstrap = ts;
        uint256 surviving = 10_000;
        for (uint256 i = 0; i < CHARGED_REBALANCES; i++) {
            bool zeroForOne = i % 2 == 0;
            _swap(zeroForOne, 5e18);
            ts += INTERVAL;
            vm.warp(ts);
            int24 lo = zeroForOne ? int24(-1200) : int24(600);
            int24 hi = zeroForOne ? int24(-600) : int24(1200);
            uint256 pre = v.totalAssetsValue();
            vm.prank(curator);
            v.rebalance(lo, hi);
            uint256 post = v.totalAssetsValue();
            uint256 loss = _lossBps(pre, post);
            surviving = FullMath.mulDiv(surviving, 10_000 - loss, 10_000);
            assertLe(loss, LOSS_CAP_BPS, "rebalance loss must respect the envelope floor");
        }

        uint256 elapsed = ts - bootstrap;
        uint256 boundCount = elapsed / INTERVAL + 1;
        uint256 bound = _boundBps(LOSS_CAP_BPS, boundCount);
        uint256 observed = 10_000 - surviving;

        string memory obj = "worstCaseLoss";
        vm.serializeUint(obj, "lossCapBps", LOSS_CAP_BPS);
        vm.serializeUint(obj, "intervalSeconds", INTERVAL);
        vm.serializeUint(obj, "elapsedSeconds", elapsed);
        vm.serializeUint(obj, "chargedRebalances", CHARGED_REBALANCES);
        vm.serializeUint(obj, "boundRebalances", boundCount);
        vm.serializeUint(obj, "boundBps", bound);
        string memory json = vm.serializeUint(obj, "observedLossBps", observed);
        if (vm.envOr("WRITE_EVIDENCE", uint256(0)) != 0) {
            vm.writeJson(json, "evidence/worst_case_loss.json");
        }

        assertGt(observed, 0, "rebalances must realize a measurable cost");
        assertLe(observed, bound, "observed rebalance loss must fit the envelope bound");
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
        ts += INTERVAL;
        vm.warp(ts);
        _swap(false, -1);
        ts += INTERVAL;
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

    function _lossBps(uint256 pre, uint256 post) internal pure returns (uint256) {
        if (post >= pre || pre == 0) return 0;
        return FullMath.mulDiv(pre - post, 10_000, pre);
    }

    function _boundBps(uint256 lossCapBps, uint256 count) internal pure returns (uint256) {
        uint256 surviving = 10_000;
        for (uint256 i = 0; i < count; i++) {
            surviving = FullMath.mulDiv(surviving, 10_000 - lossCapBps, 10_000);
        }
        return 10_000 - surviving;
    }
}
