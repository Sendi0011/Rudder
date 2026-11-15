// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title OracleTest
/// @notice Unit coverage for the hook's cumulative-tick oracle: sample bookkeeping, the two-sample
///         minimum, ring-buffer wrap-around, and the gas cost of `consult` as the sample count grows.
contract OracleTest is RudderIntegrationBase {
    uint256 internal constant DEP = 100_000e18;
    address internal lp = address(0x1D0);
    uint16 internal constant CAPACITY = 2048;

    function _prime() internal {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_envelope());
        vm.prank(curator);
        RudderVault v = RudderVault(factory.createVault(id, key, 1000));
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        token0.mint(lp, DEP);
        token1.mint(lp, DEP);
        vm.startPrank(lp);
        IERC20(address(token0)).approve(address(v), type(uint256).max);
        IERC20(address(token1)).approve(address(v), type(uint256).max);
        vm.stopPrank();
        vm.prank(lp);
        v.deposit(DEP, DEP, lp);
    }

    /// @dev Record exactly one sample at the current block, then advance the clock so the next swap
    ///      records again.
    function _sample() internal {
        _swap(true, -int256(1));
        vm.warp(block.timestamp + 1);
    }

    function _consultGas() internal view returns (uint256 g) {
        uint256 start = gasleft();
        hook.consult(key, 1800);
        g = start - gasleft();
    }

    function test_ConsultRequiresTwoSamples() public {
        _prime();
        assertEq(hook.observationCount(key), 0, "no samples before any swap");
        assertEq(hook.consult(key, 1800), 0, "no samples -> no twap");

        _sample();
        assertEq(hook.observationCount(key), 1, "one sample recorded");
        assertEq(hook.consult(key, 1800), 0, "one sample -> no twap");

        _sample();
        assertEq(hook.observationCount(key), 2, "two samples recorded");
        assertGt(hook.consult(key, 1800), 0, "two samples -> twap");
    }

    function test_OneSamplePerBlock() public {
        _prime();
        _swap(true, -int256(1));
        _swap(true, -int256(1));
        _swap(true, -int256(1));
        assertEq(hook.observationCount(key), 1, "later swaps in the same block must not add samples");
    }

    function test_RingBufferWrapsAndKeepsNewest() public {
        _prime();
        for (uint256 i = 0; i < CAPACITY + 5; i++) {
            _sample();
        }
        assertEq(hook.observationCount(key), CAPACITY, "count must cap at capacity");
        assertGt(hook.consult(key, 1800), 0, "twap must survive wrap-around");

        (uint32 ts,) = hook.getLastObservation(key);
        assertEq(ts, uint32(block.timestamp - 1), "newest sample is the most recent block");
    }

    function test_SparseSamplesStillYieldATwap() public {
        _prime();
        _sample();
        vm.warp(block.timestamp + 3600); // long gap
        _sample();
        vm.warp(block.timestamp + 3600);
        _sample();
        assertGt(hook.consult(key, 1800), 0, "sparse history must still average");
    }

    function test_ConsultGasSublinearInSampleCount() public {
        _prime();
        _sample();
        _sample();
        _sample();
        uint256 low = _consultGas();

        for (uint256 i = 0; i < 300; i++) {
            _sample();
        }
        uint256 high = _consultGas();

        emit log_named_uint("consult gas @3 samples", low);
        emit log_named_uint("consult gas @303 samples", high);
        assertLt(high, low + 60_000, "consult gas should grow sub-linearly with sample count");
    }
}
