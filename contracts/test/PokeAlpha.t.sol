// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PokeAlphaTest is RudderIntegrationBase {
    uint256 internal constant BIG = 1000e18;
    uint256 internal constant SMALL = 10e18;

    function setUp() public override {
        super.setUp();
        _fund(alice, BIG, BIG);
        vm.prank(curator);
        vault.rebalance(-600, 600);
        vm.prank(alice);
        vault.deposit(BIG, BIG, alice);
        _readyOracle();
        _fund(bob, SMALL, SMALL);
        vm.prank(bob);
        vault.deposit(SMALL, SMALL, bob);
    }

    function _readyOracle() internal {
        _swap(true, -int256(1e6));
        vm.warp(block.timestamp + 10);
        _swap(false, -int256(1e6));
        vm.warp(block.timestamp + 10);
        assertTrue(hook.isOracleReady(key));
    }

    function test_PokeAlphaAccruesWithoutFlow() public {
        token0.mint(address(vault), 100e18);
        assertTrue(hook.isOracleReady(key));

        int256 alphaBefore = vault.cumulativeAlpha();
        uint256 baseNavBefore = vault.baseNavPerShare();
        uint256 baseHoldBefore = vault.baseHoldValuePerShare();
        uint256 supplyBefore = vault.totalSupply();
        uint256 aliceSharesBefore = vault.balanceOf(alice);
        (uint256 hold0Before, uint256 hold1Before) = vault.totalHold();
        uint256 liquidityBefore = vault.positionLiquidity();
        uint256 rebalanceTsBefore = vault.lastRebalanceTimestamp();
        uint256 vault0Before = IERC20(address(token0)).balanceOf(address(vault));
        uint256 vault1Before = IERC20(address(token1)).balanceOf(address(vault));
        uint256 pending0Before = vault.pendingFees0();
        uint256 pending1Before = vault.pendingFees1();

        vm.expectEmit(true, false, false, false);
        emit RudderVault.AlphaPoked(bob, 0);
        vm.prank(bob);
        vault.pokeAlpha();

        assertGt(vault.cumulativeAlpha(), alphaBefore);
        assertGt(vault.baseNavPerShare(), baseNavBefore);
        assertEq(vault.baseHoldValuePerShare(), baseHoldBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(alice), aliceSharesBefore);
        (uint256 hold0After, uint256 hold1After) = vault.totalHold();
        assertEq(hold0After, hold0Before);
        assertEq(hold1After, hold1Before);
        assertEq(vault.positionLiquidity(), liquidityBefore);
        assertEq(vault.lastRebalanceTimestamp(), rebalanceTsBefore);
        assertEq(IERC20(address(token0)).balanceOf(address(vault)), vault0Before);
        assertEq(IERC20(address(token1)).balanceOf(address(vault)), vault1Before);
        assertEq(vault.pendingFees0(), pending0Before);
        assertEq(vault.pendingFees1(), pending1Before);
        assertEq(registry.alphaAccumulator(strategyId), vault.cumulativeAlpha());
    }

    function test_PokeAlphaNoOpsWhenOracleStale() public {
        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isOracleReady(key));

        int256 alphaBefore = vault.cumulativeAlpha();
        uint256 baseNavBefore = vault.baseNavPerShare();
        uint256 baseHoldBefore = vault.baseHoldValuePerShare();
        int256 registryBefore = registry.alphaAccumulator(strategyId);
        uint256 supplyBefore = vault.totalSupply();

        vm.recordLogs();
        vm.prank(address(0xBEEF));
        vault.pokeAlpha();

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(vault.cumulativeAlpha(), alphaBefore);
        assertEq(vault.baseNavPerShare(), baseNavBefore);
        assertEq(vault.baseHoldValuePerShare(), baseHoldBefore);
        assertEq(registry.alphaAccumulator(strategyId), registryBefore);
        assertEq(vault.totalSupply(), supplyBefore);
    }

    function test_PokeAlphaNoOpsWhenOracleCallReverts() public {
        vm.mockCallRevert(
            address(hook),
            abi.encodeWithSignature("isOracleReady((address,address,uint24,int24,address))"),
            "oracle down"
        );

        int256 alphaBefore = vault.cumulativeAlpha();
        uint256 baseNavBefore = vault.baseNavPerShare();
        int256 registryBefore = registry.alphaAccumulator(strategyId);

        vm.recordLogs();
        vm.prank(address(0xCAFE));
        vault.pokeAlpha();

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(vault.cumulativeAlpha(), alphaBefore);
        assertEq(vault.baseNavPerShare(), baseNavBefore);
        assertEq(registry.alphaAccumulator(strategyId), registryBefore);
    }

    function test_PokeAlphaRepeatedCallsDoNotDoubleCount() public {
        token0.mint(address(vault), 100e18);
        vm.prank(bob);
        vault.pokeAlpha();

        int256 alphaAfterFirst = vault.cumulativeAlpha();
        uint256 baseNavAfterFirst = vault.baseNavPerShare();
        uint256 baseHoldAfterFirst = vault.baseHoldValuePerShare();
        int256 registryAfterFirst = registry.alphaAccumulator(strategyId);

        vm.prank(bob);
        vault.pokeAlpha();

        assertEq(vault.cumulativeAlpha(), alphaAfterFirst);
        assertEq(vault.baseNavPerShare(), baseNavAfterFirst);
        assertEq(vault.baseHoldValuePerShare(), baseHoldAfterFirst);
        assertEq(registry.alphaAccumulator(strategyId), registryAfterFirst);
    }

    function test_PokeAlphaDoesNotChangeSharesOrWithdraw() public {
        token0.mint(address(vault), 100e18);
        uint256 supplyBefore = vault.totalSupply();
        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 bobSharesBefore = vault.balanceOf(bob);
        uint256 pending0Before = vault.pendingFees0();
        uint256 pending1Before = vault.pendingFees1();

        vm.prank(bob);
        vault.pokeAlpha();

        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(alice), aliceSharesBefore);
        assertEq(vault.balanceOf(bob), bobSharesBefore);
        assertEq(vault.pendingFees0(), pending0Before);
        assertEq(vault.pendingFees1(), pending1Before);

        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isOracleReady(key));
        uint256 redeem = aliceSharesBefore / 4;
        vm.prank(alice);
        (uint256 out0, uint256 out1) = vault.withdraw(redeem, alice);
        assertGt(out0 + out1, 0);
        assertEq(vault.balanceOf(alice), aliceSharesBefore - redeem);
    }
}
