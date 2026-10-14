// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RudderTestBase} from "./RudderTestBase.sol";
import {EnvelopeLib, Envelope} from "../src/libraries/EnvelopeLib.sol";
import {NAVMath} from "../src/libraries/NAVMath.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Fuzz handler that ONLY creates vaults through VaultFactory. Configured via constructor so the
///         fuzzer has no way to corrupt its wiring.
contract VaultCreationHandler is Test {
    VaultFactory internal f;
    StrategyRegistry internal reg;
    address internal cur;
    PoolKey internal key;
    Envelope internal env;

    address[] public vaults;
    uint256[] internal sids;

    /// @dev Cap vault creation so the O(n) invariant loops stay bounded across fuzz runs.
    uint256 internal constant MAX_VAULTS = 16;

    constructor(VaultFactory _f, StrategyRegistry _reg, address _c, PoolKey memory _k, Envelope memory _env) {
        f = _f;
        reg = _reg;
        cur = _c;
        key = _k;
        env = _env;
    }

    /// @dev One fresh strategy per vault, since a strategy may bind at most one vault.
    function createVault(uint16 feeCap) external {
        if (vaults.length >= MAX_VAULTS) return;
        vm.prank(cur);
        uint256 sid = reg.registerStrategy(env);
        vm.prank(cur);
        address v = f.createVault(sid, key, feeCap);
        vaults.push(v);
        sids.push(sid);
    }

    function vaultCount() external view returns (uint256) {
        return vaults.length;
    }

    function strategyIdFor(uint256 i) external view returns (uint256) {
        return sids[i];
    }
}

/// @title Invariants
/// @notice Property/fuzz tests. Vault-facing invariants ALWAYS create vaults through VaultFactory.
/// @dev The invariant functions loop over every created vault, so the search is bounded to keep the
///      suite tractable while still exercising factory-created vaults.
/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.depth = 64
contract InvariantsTest is RudderTestBase {
    VaultCreationHandler internal handler;
    uint256 internal strategyId;

    function setUp() public override {
        super.setUp();
        strategyId = _registerStrategy(curator);

        handler = new VaultCreationHandler(factory, registry, curator, _poolKey(), _envelope());
        targetContract(address(handler));
    }

    // --- pure library properties (unchanged) ---

    function checkRange(int24 width, int24 maxWidth) external pure {
        EnvelopeLib.validateRangeWidth(width, maxWidth);
    }

    function checkInterval(uint48 lastTs, uint48 nowTs, uint48 minInterval) external pure {
        EnvelopeLib.validateInterval(lastTs, nowTs, minInterval);
    }

    function checkPriceImpact(uint32 impactBps, uint32 maxImpactBps) external pure {
        EnvelopeLib.validatePriceImpact(impactBps, maxImpactBps);
    }

    function checkNavLoss(int24 lossBps, int24 maxLossBps) external pure {
        EnvelopeLib.validateNavLoss(lossBps, maxLossBps);
    }

    function checkCenterShift(int24 shift, int24 maxShift) external pure {
        EnvelopeLib.validateCenterShift(shift, maxShift);
    }

    function testFuzz_rangeWidth_enforced(int24 width, int24 maxWidth) public {
        if (width > maxWidth) {
            vm.expectRevert();
            this.checkRange(width, maxWidth);
        } else {
            this.checkRange(width, maxWidth);
        }
    }

    function testFuzz_priceImpact_enforced(uint32 impact, uint32 maxImpact) public {
        if (impact > maxImpact) {
            vm.expectRevert();
            this.checkPriceImpact(impact, maxImpact);
        } else {
            this.checkPriceImpact(impact, maxImpact);
        }
    }

    function testFuzz_navLoss_enforced(int24 loss, int24 maxLoss) public {
        if (loss < maxLoss) {
            vm.expectRevert();
            this.checkNavLoss(loss, maxLoss);
        } else {
            this.checkNavLoss(loss, maxLoss);
        }
    }

    function testFuzz_interval_enforced(uint48 lastTs, uint48 nowTs, uint48 minInterval) public {
        bool tooShort = nowTs < lastTs || (uint256(nowTs) - uint256(lastTs)) < uint256(minInterval);
        if (tooShort) {
            vm.expectRevert();
            this.checkInterval(lastTs, nowTs, minInterval);
        } else {
            this.checkInterval(lastTs, nowTs, minInterval);
        }
    }

    function testFuzz_fee_neverExceedsCap(uint256 gain, uint256 maxFeeBps, uint256 feeBps) public {
        gain = bound(gain, 0, 1e30);
        maxFeeBps = bound(maxFeeBps, 0, 10000);
        feeBps = bound(feeBps, 0, 10000);
        uint256 holdValue = 1000;
        uint256 depositorValue = holdValue + gain;
        uint256 fee = NAVMath.computePerformanceFee(depositorValue, holdValue, maxFeeBps, feeBps);
        uint256 capAmount = MathLib.mulDivDown(gain, maxFeeBps, 10000);
        assertLe(fee, capAmount);
    }

    function testFuzz_fee_zeroOnLoss(uint256 a, uint256 b) public {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);
        if (a <= b) {
            uint256 fee = NAVMath.computePerformanceFee(a, b, 2000, 1000);
            assertEq(fee, 0);
        }
    }

    function testFuzz_proportional_neverExceeds(uint256 amount, uint256 shares, uint256 totalShares) public {
        amount = bound(amount, 0, 1e30);
        totalShares = bound(totalShares, 1, 1e30);
        shares = bound(shares, 0, totalShares);
        NAVMath.Basket memory total = NAVMath.Basket({amount0: amount, amount1: amount});
        NAVMath.Basket memory outB = NAVMath.proportionalBasket(total, shares, totalShares);
        assertLe(outB.amount0, amount);
        assertLe(outB.amount1, amount);
    }

    function testFuzz_proportional_splitConservation(uint256 amount, uint256 s1, uint256 s2) public {
        amount = bound(amount, 0, 1e30);
        s1 = bound(s1, 0, 1e18);
        s2 = bound(s2, 0, 1e18);
        uint256 totalShares = s1 + s2;
        if (totalShares == 0) return;
        NAVMath.Basket memory total = NAVMath.Basket({amount0: amount, amount1: amount});
        NAVMath.Basket memory a = NAVMath.proportionalBasket(total, s1, totalShares);
        NAVMath.Basket memory b = NAVMath.proportionalBasket(total, s2, totalShares);
        assertLe(a.amount0 + b.amount0, amount);
    }

    // --- factory-created vault invariants ---

    /// @notice Every vault produced by the handler is registered by the factory, bound to the
    ///         strategy, and carries the strategy's curator.
    function invariant_allCreatedVaultsRegistered() public view {
        uint256 n = handler.vaultCount();
        for (uint256 i = 0; i < n; i++) {
            address v = handler.vaults(i);
            assertTrue(factory.isVault(v), "vault must be registered");
            assertEq(factory.vaultToStrategyId(v), handler.strategyIdFor(i), "vault bound to strategy");
            assertEq(RudderVault(v).curator(), curator, "curator bound");
        }
    }

    /// @notice Every factory-created vault clamps its fee cap to the protocol maximum.
    function invariant_feeCapWithinProtocolMax() public view {
        uint256 n = handler.vaultCount();
        for (uint256 i = 0; i < n; i++) {
            assertLe(RudderVault(handler.vaults(i)).feeCapBps(), factory.PROTOCOL_MAX_FEE_BPS(), "fee cap bounded");
        }
    }
}
