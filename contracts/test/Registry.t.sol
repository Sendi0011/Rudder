// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {Envelope, EnvelopeLib} from "../src/libraries/EnvelopeLib.sol";

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
            maxTwapDistanceTicks: 1000,
            minRebalanceInterval: 60,
            maxPriceImpactBps: 50,
            maxNavLossBps: -500
        });
    }

    function _registerBound(address _curator, address _vault) internal returns (uint256 id) {
        vm.prank(_curator);
        id = registry.registerStrategy(_env());
        vm.prank(factory);
        registry.setStrategyVault(id, _vault);
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
            maxTwapDistanceTicks: 1000,
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
            maxTwapDistanceTicks: 1000,
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

    address factory = address(0xFAC);

    function test_SetFactory_Once() public {
        registry.setFactory(factory);
        assertEq(registry.factory(), factory);
        vm.expectRevert(StrategyRegistry.FactoryAlreadySet.selector);
        registry.setFactory(address(0xBAD));
    }

    function test_SetFactory_OnlyOwner() public {
        vm.prank(address(0xB0B));
        vm.expectRevert(StrategyRegistry.Unauthorized.selector);
        registry.setFactory(factory);
    }

    function test_BindVault_OnlyFactory() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(curator);
        vm.expectRevert(StrategyRegistry.Unauthorized.selector);
        registry.setStrategyVault(id, vault);
    }

    function test_BindVault_RevertsIfAlreadyBound() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(factory);
        registry.setStrategyVault(id, vault);
        vm.prank(factory);
        vm.expectRevert(StrategyRegistry.StrategyAlreadyBound.selector);
        registry.setStrategyVault(id, address(0xABCD));
    }

    function test_BindVault_RevertsForUnknownStrategy() public {
        registry.setFactory(factory);
        vm.prank(factory);
        vm.expectRevert(StrategyRegistry.UnknownStrategy.selector);
        registry.setStrategyVault(999, vault);
    }

    function test_CheckpointAlpha() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(factory);
        registry.setStrategyVault(id, vault);
        vm.prank(vault);
        registry.checkpointAlpha(id, 100);
        vm.prank(vault);
        registry.checkpointAlpha(id, 170);
        assertEq(registry.getAlpha(id), 70);
    }

    function test_CheckpointAlpha_SingleSampleScoresZero() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(factory);
        registry.setStrategyVault(id, vault);
        vm.prank(vault);
        registry.checkpointAlpha(id, 100);
        assertEq(registry.getAlpha(id), 0);
    }

    function test_AlphaAtCutoffIsInterpolated() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(factory);
        registry.setStrategyVault(id, vault);
        vm.prank(vault);
        registry.checkpointAlpha(id, 0);
        vm.warp(block.timestamp + 40 days);
        vm.prank(vault);
        registry.checkpointAlpha(id, 60);
        vm.warp(block.timestamp + 5 days);
        vm.prank(vault);
        registry.checkpointAlpha(id, 100);

        // The 30-day cutoff falls 15/40 of the way from the first sample (0) to the second (60),
        // so the cutoff accumulator is 22 and the score is 100 - 22 == 78.
        assertEq(registry.alphaSamples(id), 3);
        assertEq(registry.getAlpha(id), 78);
    }

    function test_AlphaHistoryBoundedByRingBuffer() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(factory);
        registry.setStrategyVault(id, vault);

        uint256 cap = registry.MAX_CHECKPOINTS();
        // Advance a local clock rather than re-reading block.timestamp: via-ir hoists that read out
        // of the loop, so `vm.warp(block.timestamp + 1 hours)` would not progress under the optimizer.
        uint256 t = block.timestamp;
        for (uint256 i = 0; i < cap + 25; i++) {
            t += 1 hours;
            vm.warp(t);
            vm.prank(vault);
            registry.checkpointAlpha(id, int256(i));
        }

        // The ring keeps only the newest `cap` samples; the 25 oldest are overwritten.
        assertEq(registry.alphaSamples(id), cap, "history must be bounded by the ring");
        assertEq(registry.getAlpha(id), int256(cap + 24) - int256(25));
    }

    function test_MidWindowDepositCheckpointDoesNotChangeScore() public {
        registry.setFactory(factory);
        uint256 withDeposit = _registerBound(address(0xA1), address(0xB1));
        uint256 plain = _registerBound(address(0xA2), address(0xB2));
        int256 alpha = 1e16;
        uint256 base = vm.getBlockTimestamp();
        uint256 finalTime = base + 40 days;

        vm.prank(address(0xB1));
        registry.checkpointAlpha(withDeposit, 0);
        vm.prank(address(0xB2));
        registry.checkpointAlpha(plain, 0);

        vm.warp(base + 20 days);
        vm.prank(address(0xB1));
        registry.checkpointAlpha(withDeposit, alpha / 2);

        vm.warp(finalTime);
        vm.prank(address(0xB1));
        registry.checkpointAlpha(withDeposit, alpha);
        vm.prank(address(0xB2));
        registry.checkpointAlpha(plain, alpha);

        vm.warp(finalTime);
        int256 withDepositScore = registry.getAlpha(withDeposit);
        vm.warp(finalTime);
        int256 plainScore = registry.getAlpha(plain);
        assertEq(withDepositScore, plainScore);
        assertEq(plainScore, alpha - alpha / 4);
    }

    function test_MidWindowWithdrawalCheckpointDoesNotChangeScore() public {
        registry.setFactory(factory);
        uint256 withWithdrawal = _registerBound(address(0xA1), address(0xB1));
        uint256 plain = _registerBound(address(0xA2), address(0xB2));
        int256 alpha = 1e16;
        uint256 base = vm.getBlockTimestamp();
        uint256 finalTime = base + 40 days;

        vm.prank(address(0xB1));
        registry.checkpointAlpha(withWithdrawal, 0);
        vm.prank(address(0xB2));
        registry.checkpointAlpha(plain, 0);

        vm.warp(base + 20 days);
        vm.prank(address(0xB1));
        registry.checkpointAlpha(withWithdrawal, alpha / 2);

        vm.warp(finalTime);
        vm.prank(address(0xB1));
        registry.checkpointAlpha(withWithdrawal, alpha);
        vm.prank(address(0xB2));
        registry.checkpointAlpha(plain, alpha);

        vm.warp(finalTime);
        int256 withWithdrawalScore = registry.getAlpha(withWithdrawal);
        vm.warp(finalTime);
        int256 plainScore = registry.getAlpha(plain);
        assertEq(withWithdrawalScore, plainScore);
        assertEq(plainScore, alpha - alpha / 4);
    }

    function test_GetAlphaGasIsSublinearInHistoryLength() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        registry.setFactory(factory);
        vm.prank(factory);
        registry.setStrategyVault(id, vault);

        uint256 t = block.timestamp;
        for (uint256 i = 0; i < 10; i++) {
            t += 1 hours;
            vm.warp(t);
            vm.prank(vault);
            registry.checkpointAlpha(id, int256(i));
        }
        uint256 start = gasleft();
        registry.getAlpha(id);
        uint256 shortGas = start - gasleft();

        for (uint256 i = 10; i < registry.MAX_CHECKPOINTS(); i++) {
            t += 1 hours;
            vm.warp(t);
            vm.prank(vault);
            registry.checkpointAlpha(id, int256(i));
        }
        start = gasleft();
        registry.getAlpha(id);
        uint256 longGas = start - gasleft();

        assertLt(longGas, shortGas + 50_000, "binary search should not scan the whole ring");
    }

    function test_LeaderboardPageIsBounded() public {
        registry.setFactory(factory);
        for (uint256 i = 0; i < 101; i++) {
            vm.prank(address(uint160(0xA000 + i)));
            uint256 id = registry.registerStrategy(_env());
            vm.prank(factory);
            registry.setStrategyVault(id, address(uint160(0xB000 + i)));
        }
        assertEq(registry.rankedCount(), 101);

        (uint256[] memory first, int256[] memory firstScores) = registry.leaderboard(1000);
        assertEq(first.length, registry.MAX_LEADERBOARD_PAGE());
        assertEq(firstScores.length, first.length);

        (uint256[] memory page, int256[] memory pageScores) = registry.leaderboardPage(99, 10);
        assertEq(page.length, 2);
        assertEq(pageScores.length, 2);
        assertEq(page[0], 99);
    }

    function test_Leaderboard_OrdersByIntervalAlpha() public {
        registry.setFactory(factory);
        address[3] memory curators = [address(0xA1), address(0xA2), address(0xA3)];
        int256[3] memory deltas = [int256(30), int256(120), int256(60)];
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(curators[i]);
            uint256 id = registry.registerStrategy(_env());
            address v = address(uint160(0xF000 + i));
            vm.prank(factory);
            registry.setStrategyVault(id, v);
            vm.prank(v);
            registry.checkpointAlpha(id, 0);
            vm.prank(v);
            registry.checkpointAlpha(id, deltas[i]);
        }

        (uint256[] memory ids, int256[] memory scores) = registry.leaderboard(2);
        assertEq(ids.length, 2);
        assertEq(scores[0], 120);
        assertEq(scores[1], 60);
    }

    function test_TightenRevertsWhenAnyFieldLooser() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        Envelope memory looser = _env();
        looser.maxRangeWidth = 2000; // one field looser, rest identical
        vm.prank(curator);
        vm.expectRevert(EnvelopeLib.NotTighter.selector);
        registry.tightenEnvelope(id, looser);
    }

    function test_RegisterRejectsDegenerateEnvelope() public {
        Envelope memory bad = _env();
        bad.maxRangeWidth = 0;
        vm.expectRevert(EnvelopeLib.InvalidParams.selector);
        registry.registerStrategy(bad);
    }

    function test_CheckpointAlpha_Unauthorized() public {
        vm.prank(curator);
        uint256 id = registry.registerStrategy(_env());
        vm.expectRevert(StrategyRegistry.Unauthorized.selector);
        registry.checkpointAlpha(id, 100);
    }
}
