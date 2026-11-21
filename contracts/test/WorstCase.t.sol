// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";

contract WorstCaseTest is RudderIntegrationBase {
    uint256 internal constant DEP = 1000e18;

    function test_WidestEnvelopeRangeIsAccepted() public {
        vm.prank(curator);
        vault.rebalance(-3000, 3000);

        assertEq(vault.tickLower(), -3000);
        assertEq(vault.tickUpper(), 3000);
        assertEq(vault.tickUpper() - vault.tickLower(), 6000);
    }

    function test_FeeCapIsClampedAtProtocolMax() public {
        uint256 id;
        vm.prank(curator);
        id = registry.registerStrategy(_envelope());

        vm.prank(curator);
        RudderVault v = RudderVault(factory.createVault(id, key, type(uint16).max));

        assertEq(v.feeCapBps(), v.PROTOCOL_MAX_FEE_BPS());
    }

    function test_OracleAtMaxAgeBlocksDepositButNotWithdraw() public {
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _fund(alice, DEP, DEP);
        uint256 shares = _deposit(alice, DEP, DEP);
        _readyOracle();
        vm.prank(curator);
        vault.rebalance(-600, 600);

        (uint32 lastTs,) = hook.getLastObservation(key);
        vm.warp(uint256(lastTs) + hook.MAX_OBSERVATION_AGE());
        assertTrue(hook.isOracleReady(key));

        vm.warp(block.timestamp + 1);
        assertFalse(hook.isOracleReady(key));

        token0.mint(alice, 1e18);
        token1.mint(alice, 1e18);
        _approve(alice, address(vault));
        vm.expectRevert(RudderVault.OracleBad.selector);
        vm.prank(alice);
        vault.deposit(1, 1, alice);

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = vault.withdraw(shares, alice);
        assertGt(amount0 + amount1, 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_StaleOracleWithdrawAtMaxFeeCapAccruesNoFee() public {
        uint256 id;
        vm.prank(curator);
        id = registry.registerStrategy(_envelope());

        vm.prank(curator);
        RudderVault v = RudderVault(factory.createVault(id, key, type(uint16).max));
        token0.mint(alice, DEP);
        token1.mint(alice, DEP);
        _approve(alice, address(v));

        vm.prank(curator);
        v.rebalance(-600, 600);
        vm.prank(alice);
        uint256 shares = v.deposit(DEP, DEP, alice);

        vm.warp(block.timestamp + hook.MAX_OBSERVATION_AGE() + 1);
        assertFalse(hook.isOracleReady(key));

        vm.prank(alice);
        v.withdraw(shares, alice);
        assertEq(v.pendingFees0(), 0);
        assertEq(v.pendingFees1(), 0);
    }

    function _readyOracle() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(false, -int256(1e6));
        vm.warp(block.timestamp + 10);
        assertTrue(hook.isOracleReady(key));
    }
}
