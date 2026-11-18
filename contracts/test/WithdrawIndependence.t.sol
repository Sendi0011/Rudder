// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract WithdrawIndependenceTest is RudderIntegrationBase {
    uint256 internal constant DEP = 1000e18;
    uint256 internal aliceShares;

    function setUp() public override {
        super.setUp();
        _fund(alice, DEP, DEP);
        _fund(bob, DEP + 1e15, DEP + 1e15);
        vm.prank(curator);
        vault.rebalance(-600, 600);
        vm.prank(alice);
        aliceShares = vault.deposit(DEP, DEP, alice);
        vm.prank(bob);
        vault.deposit(DEP, DEP, bob);
    }

    function test_WithdrawWithStaleOraclePaysProRata() public {
        _readyOracle();
        vm.prank(curator);
        vault.rebalance(-600, 600);
        vm.warp(block.timestamp + hook.MAX_OBSERVATION_AGE() + 1);
        assertFalse(hook.isOracleReady(key));
        _assertProRata();
    }

    function test_WithdrawWithFewerThanTwoSamplesPaysProRata() public {
        assertLt(hook.observationCount(key), 2);
        assertFalse(hook.isOracleReady(key));
        _assertProRata();
    }

    function test_WithdrawWithConsultRevertPaysProRata() public {
        _readyOracle();
        vm.prank(curator);
        vault.rebalance(-600, 600);
        vm.mockCallRevert(
            address(hook),
            abi.encodeWithSignature("consult((address,address,uint24,int24,address),uint32)"),
            "consult down"
        );
        _assertProRata(100);
    }

    function test_WithdrawWithRegistryRevertPaysProRata() public {
        _readyOracle();
        vm.prank(bob);
        vault.deposit(1e15, 1e15, bob);
        vm.mockCallRevert(
            address(registry), abi.encodeWithSelector(StrategyRegistry.checkpointAlpha.selector), "registry down"
        );
        _assertProRata();
    }

    function test_WithdrawWithPausedHookPaysProRata() public {
        hook.setPaused(true);
        assertTrue(hook.paused());
        _assertProRata();
    }

    function test_WithdrawSourceOnlyUsesAllowedCalls() public {
        string memory src = vm.readFile("contracts/src/RudderVault.sol");
        uint256 start = _indexOf(src, "function withdraw(uint256 shares, address recipient)");
        uint256 end = _indexOf(src, "function claimFees()");
        require(start != type(uint256).max && end > start, "withdraw body not found");
        string memory body = _slice(src, start, end - start);

        bytes memory b = bytes(body);
        for (uint256 i; i + 1 < b.length; ++i) {
            if (b[i] == ".") {
                uint256 j = i + 1;
                while (j < b.length && _isIdentifier(bytes1(b[j]))) ++j;
                if (j < b.length && b[j] == "(") {
                    string memory callName = _slice(body, i + 1, j - i - 1);
                    assertTrue(_allowedCall(callName), string.concat("unexpected external call: ", callName));
                }
            }
        }
        assertEq(_count(body, ".safeTransfer("), 2, "expected two token payouts");
    }

    function _readyOracle() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(false, -int256(1e6));
        vm.warp(block.timestamp + 10);
        assertTrue(hook.isOracleReady(key));
    }

    function _assertProRata() internal {
        _assertProRata(0);
    }

    function _assertProRata(uint256 tolerance) internal {
        (uint256 expected0, uint256 expected1) = _expectedPayout(aliceShares);
        uint256 before0 = IERC20(address(token0)).balanceOf(alice);
        uint256 before1 = IERC20(address(token1)).balanceOf(alice);
        uint256 pending0 = vault.pendingFees0();
        uint256 pending1 = vault.pendingFees1();

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = vault.withdraw(aliceShares, alice);

        assertApproxEqAbs(amount0, expected0, tolerance, "token0 payout is not pro-rata");
        assertApproxEqAbs(amount1, expected1, tolerance, "token1 payout is not pro-rata");
        assertApproxEqAbs(IERC20(address(token0)).balanceOf(alice) - before0, expected0, tolerance, "token0 balance");
        assertApproxEqAbs(IERC20(address(token1)).balanceOf(alice) - before1, expected1, tolerance, "token1 balance");
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.pendingFees0(), pending0, "withdraw accrued fee0");
        assertEq(vault.pendingFees1(), pending1, "withdraw accrued fee1");
    }

    function _expectedPayout(uint256 shares) internal view returns (uint256 expected0, uint256 expected1) {
        uint256 supply = vault.totalSupply();
        uint128 liquidity = vault.positionLiquidity();
        uint128 removedLiquidity = uint128((uint256(liquidity) * shares) / supply);
        uint160 sqrtP = _sqrtPrice();
        (uint256 removed0, uint256 removed1) = _burnedAmounts(sqrtP, removedLiquidity);
        uint256 idle0 = IERC20(address(token0)).balanceOf(address(vault)) - vault.pendingFees0();
        uint256 idle1 = IERC20(address(token1)).balanceOf(address(vault)) - vault.pendingFees1();
        expected0 = removed0 + (idle0 * shares) / supply;
        expected1 = removed1 + (idle1 * shares) / supply;
    }

    function _burnedAmounts(uint160 sqrtP, uint128 liquidity) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(vault.tickLower());
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(vault.tickUpper());
        if (sqrtP <= sqrtA) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtA, sqrtB, liquidity, false);
        } else if (sqrtP < sqrtB) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtP, sqrtB, liquidity, false);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtP, liquidity, false);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtB, liquidity, false);
        }
    }

    function _allowedCall(string memory name) internal pure returns (bool) {
        return _eq(name, "safeTransfer") || _eq(name, "unwrap");
    }

    function _isIdentifier(bytes1 c) internal pure returns (bool) {
        uint8 x = uint8(c);
        return (x >= 48 && x <= 57) || (x >= 65 && x <= 90) || (x >= 97 && x <= 122) || x == 95;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _indexOf(string memory text, string memory pattern) internal pure returns (uint256) {
        bytes memory t = bytes(text);
        bytes memory p = bytes(pattern);
        if (p.length == 0 || p.length > t.length) return type(uint256).max;
        for (uint256 i; i + p.length <= t.length; ++i) {
            bool isMatch = true;
            for (uint256 j; j < p.length; ++j) {
                if (t[i + j] != p[j]) {
                    isMatch = false;
                    break;
                }
            }
            if (isMatch) return i;
        }
        return type(uint256).max;
    }

    function _slice(string memory text, uint256 start, uint256 len) internal pure returns (string memory) {
        bytes memory t = bytes(text);
        bytes memory out = new bytes(len);
        for (uint256 i; i < len; ++i) {
            out[i] = t[start + i];
        }
        return string(out);
    }

    function _count(string memory text, string memory pattern) internal pure returns (uint256 n) {
        bytes memory t = bytes(text);
        bytes memory p = bytes(pattern);
        if (p.length == 0) return 0;
        for (uint256 i; i + p.length <= t.length; ++i) {
            bool isMatch = true;
            for (uint256 j; j < p.length; ++j) {
                if (t[i + j] != p[j]) {
                    isMatch = false;
                    break;
                }
            }
            if (isMatch) ++n;
        }
    }
}
