// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";

contract RegistryTest is Test {
    StrategyRegistry registry;
    address curator = address(0xCAFE);
    address vault = address(0xBEEF);

    function setUp() public {
        registry = new StrategyRegistry();
    }

    function _env() internal pure returns (Envelope memory) {
        return Envelope({
            maxRangeWidth: 1000,
            maxCenterShift: 500,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500
        });
    }

    function test_RegisterStrategy() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        assertEq(id, 0);
        assertTrue(registry.isCurator(id, curator));
    }

    function test_TightenInstant() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        Envelope memory tighter = Envelope({
            maxRangeWidth: 500,
            maxCenterShift: 250,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500
        });
        vm.prank(curator);
        registry.tightenEnvelope(id, tighter);
        assertEq(registry.getEnvelope(id).maxRangeWidth, 500);
    }

    function test_LoosenTimelock() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        Envelope memory looser = Envelope({
            maxRangeWidth: 2000,
            maxCenterShift: 1000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500
        });
        vm.prank(curator);
        registry.queueLoosenEnvelope(id, looser);
        // apply too early reverts
        vm.prank(curator);
        vm.expectRevert(StrategyRegistry.TimelockNotReady.selector);
        registry.applyLoosenEnvelope(id);
        // after delay
        vm.warp(block.timestamp + 24 hours);
        vm.prank(curator);
        registry.applyLoosenEnvelope(id);
        assertEq(registry.getEnvelope(id).maxRangeWidth, 2000);
    }

    function test_CheckpointAlpha() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        vm.prank(curator);
        registry.setStrategyVault(id, vault);
        vm.prank(vault);
        registry.checkpointAlpha(id, 100);
        vm.prank(vault);
        registry.checkpointAlpha(id, -30);
        assertEq(registry.getAlpha(id), 70);
    }

    function test_CheckpointAlpha_Unauthorized() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        vm.expectRevert(StrategyRegistry.Unauthorized.selector);
        registry.checkpointAlpha(id, 100);
    }
}
