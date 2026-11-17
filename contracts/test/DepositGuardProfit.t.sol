// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {LiquidityLib} from "../src/libraries/LiquidityLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title DepositGuardProfitTest
/// @notice Quantifies the best round-trip profit an attacker can extract by pushing the spot to the
///         largest deviation the deposit guard tolerates, depositing (priced at TWAP) and withdrawing
///         immediately. The measured leak is compared against the pool's swap fee, which is what the
///         attacker must pay to create the deviation in the first place.
contract DepositGuardProfitTest is RudderIntegrationBase {
    uint256 internal constant DEP = 1000e18;
    uint256 internal constant DEEP = 100_000e18;
    uint256 internal constant FEE_BPS = 30; // key.fee == 3000 (0.30%)
    address internal lp = address(0x1D0);
    address internal attacker = address(0xA77ACCE7);

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

    function _depthVault(uint256 amount) internal returns (RudderVault deep) {
        deep = _newVault(_envelope());
        vm.prank(curator);
        deep.rebalance(-3000, 3000);
        _fundVault(deep, lp, amount, amount);
        vm.prank(lp);
        deep.deposit(amount, amount, lp);
    }

    function _readyPool() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
    }

    function _prime() internal returns (RudderVault v) {
        v = _newVault(_envelope());
        vm.prank(curator);
        v.rebalance(-3000, 3000);
        _fundVault(v, alice, DEP, DEP);
        vm.prank(alice);
        v.deposit(DEP, DEP, alice);
        _depthVault(DEEP);
        _readyPool();
    }

    function _devBps(uint160 spot, uint160 twap) internal pure returns (uint256) {
        uint256 diff = spot > twap ? uint256(spot - twap) : uint256(twap - spot);
        return (diff * 10000) / uint256(twap);
    }

    /// @dev Value of the attacker's whole wallet in token0 at `sqrtP`.
    function _walletValue(address who, uint160 sqrtP) internal view returns (uint256) {
        return LiquidityLib.valueInToken0(token0.balanceOf(who), token1.balanceOf(who), sqrtP);
    }

    // ------------------------------------------------------------------
    // the number
    // ------------------------------------------------------------------

    /// @notice Round-trip at the maximum tolerated deviation. Logs the deviation and the leak in bps
    ///         of the deposited value, and requires the leak to stay under the swap fee.
    function test_BestRoundTripProfitBelowSwapFee() public {
        RudderVault v = _prime();

        _fundVault(v, attacker, DEP, DEP);
        uint160 twap = v.twapSqrtPrice();
        uint256 startVal = _walletValue(attacker, twap);

        // Push the spot toward the guard's cap (50 sqrt-bps) in the same block as the deposit.
        _swap(true, -int256(3500e18));
        uint160 spot = _sqrtPrice();
        uint256 dev = _devBps(spot, twap);

        vm.prank(attacker);
        uint256 shares = v.deposit(DEP, DEP, attacker);
        vm.prank(attacker);
        v.withdraw(shares, attacker);

        uint256 endVal = _walletValue(attacker, twap);
        uint256 depVal = LiquidityLib.valueInToken0(DEP, DEP, twap);

        emit log_named_uint("deviation bps", dev);
        emit log_named_uint("deposited value0", depVal);
        if (endVal > startVal) {
            uint256 leakBps = ((endVal - startVal) * 10000) / depVal;
            emit log_named_uint("round-trip leak bps", leakBps);
            assertLt(leakBps, FEE_BPS, "round-trip leak exceeds the swap fee");
        } else {
            emit log_named_int("round-trip loss0", -int256(startVal - endVal));
        }
    }

    /// @notice The same round trip with the spot pushed the other way. Logs the deviation and leak.
    function test_BestRoundTripProfitOppositeDirection() public {
        RudderVault v = _prime();

        _fundVault(v, attacker, DEP, DEP);
        uint160 twap = v.twapSqrtPrice();
        uint256 startVal = _walletValue(attacker, twap);

        _swap(false, -int256(3500e18));
        uint160 spot = _sqrtPrice();
        uint256 dev = _devBps(spot, twap);

        vm.prank(attacker);
        uint256 shares = v.deposit(DEP, DEP, attacker);
        vm.prank(attacker);
        v.withdraw(shares, attacker);

        uint256 endVal = _walletValue(attacker, twap);
        uint256 depVal = LiquidityLib.valueInToken0(DEP, DEP, twap);
        emit log_named_uint("opposite deviation bps", dev);
        if (endVal > startVal) {
            uint256 leakBps = ((endVal - startVal) * 10000) / depVal;
            emit log_named_uint("opposite round-trip leak bps", leakBps);
            assertLt(leakBps, FEE_BPS, "opposite-direction leak exceeds the swap fee");
        } else {
            emit log_named_int("opposite round-trip loss0", -int256(startVal - endVal));
        }
    }

    /// @notice A token1-heavy deposit priced at the same tolerated deviation cannot leak past the fee.
    function test_Token1HeavyRoundTripProfitBelowSwapFee() public {
        RudderVault v = _prime();
        uint256 amount0 = DEP / 4;
        uint256 amount1 = DEP * 3;

        _fundVault(v, attacker, amount0, amount1);
        uint160 twap = v.twapSqrtPrice();
        uint256 startVal = _walletValue(attacker, twap);

        _swap(true, -int256(3500e18));
        uint160 spot = _sqrtPrice();
        uint256 dev = _devBps(spot, twap);

        vm.prank(attacker);
        uint256 shares = v.deposit(amount0, amount1, attacker);
        vm.prank(attacker);
        v.withdraw(shares, attacker);

        uint256 endVal = _walletValue(attacker, twap);
        uint256 depVal = LiquidityLib.valueInToken0(amount0, amount1, twap);
        emit log_named_uint("token1-heavy deviation bps", dev);
        if (endVal > startVal) {
            uint256 leakBps = ((endVal - startVal) * 10000) / depVal;
            emit log_named_uint("token1-heavy leak bps", leakBps);
            assertLt(leakBps, FEE_BPS, "token1-heavy leak exceeds the swap fee");
        } else {
            emit log_named_int("token1-heavy round-trip loss0", -int256(startVal - endVal));
        }
    }

    /// @notice With the spot at the TWAP (no manipulation) the round trip cannot leak at all.
    function test_RoundTripAtTwapLeaksNothing() public {
        RudderVault v = _prime();

        _fundVault(v, attacker, DEP, DEP);
        uint160 twap = v.twapSqrtPrice();
        uint256 startVal = _walletValue(attacker, twap);

        vm.prank(attacker);
        uint256 shares = v.deposit(DEP, DEP, attacker);
        vm.prank(attacker);
        v.withdraw(shares, attacker);

        uint256 endVal = _walletValue(attacker, twap);
        uint256 depVal = LiquidityLib.valueInToken0(DEP, DEP, twap);
        assertLe(endVal, startVal + depVal / 10_000, "unmanipulated round trip should not leak");
    }

    /// @notice A spot beyond the guard's ceiling is rejected outright, so the extreme deviation is
    ///         not even reachable for a deposit.
    function test_DepositRejectedBeyondGuardCap() public {
        RudderVault v = _prime();

        _fundVault(v, attacker, DEP, DEP);
        _swap(true, -int256(20_000e18)); // far beyond the 50 sqrt-bps cap

        vm.prank(attacker);
        vm.expectRevert();
        v.deposit(DEP, DEP, attacker);
    }
}
