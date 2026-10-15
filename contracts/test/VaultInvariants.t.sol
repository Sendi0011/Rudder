// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RudderIntegrationBase} from "./RudderIntegrationBase.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";
import {MiniSwapRouter} from "./RudderIntegrationBase.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {LiquidityLib} from "../src/libraries/LiquidityLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Drives the vault through randomized deposit/withdraw/swap/rebalance against the real
///         PoolManager. All actions are bounded so they are expected to succeed (never revert),
///         which lets the invariant suite assert post-conditions after every sequence.
contract VaultHandler is Test {
    RudderVault public immutable vault;
    TestERC20 internal immutable t0;
    TestERC20 internal immutable t1;
    MiniSwapRouter internal immutable router;
    PoolKey internal key;
    StrategyRegistry internal immutable registry;
    uint256 internal immutable strategyId;
    address internal curator;
    address[3] internal actors;

    constructor(
        RudderVault _vault,
        TestERC20 _t0,
        TestERC20 _t1,
        MiniSwapRouter _router,
        PoolKey memory _key,
        StrategyRegistry _registry,
        uint256 _strategyId,
        address _curator,
        address[3] memory _actors
    ) {
        vault = _vault;
        t0 = _t0;
        t1 = _t1;
        router = _router;
        key = _key;
        registry = _registry;
        strategyId = _strategyId;
        curator = _curator;
        actors = _actors;

        for (uint256 i = 0; i < actors.length; i++) {
            t0.mint(actors[i], 1e30);
            t1.mint(actors[i], 1e30);
            vm.startPrank(actors[i]);
            IERC20(address(t0)).approve(address(vault), type(uint256).max);
            IERC20(address(t1)).approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }

        // Bootstrap a working vault and make the pool oracle-ready.
        vm.prank(curator);
        vault.rebalance(-600, 600);
        _deposit(0, 50_000e18, 50_000e18);
        _swap(true, 1e17);
        vm.warp(block.timestamp + 10);
        _swap(true, 1e17);
        vm.warp(block.timestamp + 10);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _swap(bool zeroForOne, uint256 amount) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(key, zeroForOne, -int256(amount), limit);
    }

    function _deposit(uint256 seed, uint256 amount0, uint256 amount1) internal {
        address who = _actor(seed);
        vm.prank(who);
        vault.deposit(amount0, amount1, who);
    }

    function deposit(uint256 seed, uint256 amount0, uint256 amount1) external {
        address who = _actor(seed);
        amount0 = bound(amount0, 1e15, 100_000e18);
        amount1 = bound(amount1, 0, 100_000e18);
        t0.mint(who, amount0);
        t1.mint(who, amount1);
        vm.prank(who);
        vault.deposit(amount0, amount1, who);
    }

    function withdraw(uint256 seed, uint256 shares) external {
        address who = _actor(seed);
        uint256 bal = vault.balanceOf(who);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(who);
        vault.withdraw(shares, who);
    }

    function swap(uint256 seed, uint256 amount) external {
        amount = bound(amount, 1e15, 5e17);
        bool zeroForOne = seed % 2 == 0;
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(key, zeroForOne, -int256(amount), limit);
        vm.warp(block.timestamp + 10);
    }

    function rebalance(uint256 seed) external {
        vm.warp(block.timestamp + 100);
        (int24 lo, int24 hi) = seed % 2 == 0 ? (int24(-600), int24(600)) : (int24(-300), int24(300));
        vm.prank(curator);
        vault.rebalance(lo, hi);
    }
}

/// @notice Stateful invariants: share conservation, protocol fee bound, and the envelope's range
///         width is never exceeded by a live position.
contract VaultInvariantsTest is RudderIntegrationBase {
    VaultHandler internal handler;
    address[3] internal actors;

    function setUp() public override {
        super.setUp();
        actors = [alice, bob, address(0xCA401)];
        handler = new VaultHandler(vault, token0, token1, router, key, registry, strategyId, curator, actors);

        bytes4[] memory sels = new bytes4[](4);
        sels[0] = VaultHandler.deposit.selector;
        sels[1] = VaultHandler.withdraw.selector;
        sels[2] = VaultHandler.swap.selector;
        sels[3] = VaultHandler.rebalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    function invariant_ShareConservation() public view {
        uint256 held = vault.balanceOf(actors[0]) + vault.balanceOf(actors[1]) + vault.balanceOf(actors[2])
            + vault.balanceOf(address(vault));
        assertEq(held, vault.totalSupply(), "shares must sum to total supply");
    }

    function invariant_FeeCapWithinProtocolMax() public view {
        assertLe(vault.feeCapBps(), vault.PROTOCOL_MAX_FEE_BPS(), "fee cap exceeds protocol max");
    }

    function invariant_EnvelopeWidthRespected() public view {
        if (vault.rangeSet()) {
            Envelope memory env = registry.getEnvelope(strategyId);
            assertLe(vault.tickUpper() - vault.tickLower(), env.maxRangeWidth, "range exceeds envelope");
        }
    }

    /// @notice Solvency: the vault's real holdings (idle + position, valued at the same TWAP the vault
    ///         uses) must cover what it reports as LP-owned NAV plus the curator's pending fees. In
    ///         other words the vault never promises a redemption it cannot back with tokens.
    function invariant_HoldingsCoverRedemptions() public view {
        uint160 sqrtP = vault.twapSqrtPrice();

        uint256 idle0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(vault));
        uint256 idle1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(vault));
        uint256 holdings = LiquidityLib.valueInToken0(idle0, idle1, sqrtP);
        if (vault.positionLiquidity() > 0) {
            (uint256 p0, uint256 p1) = LiquidityLib.getAmountsForLiquidity(
                sqrtP,
                TickMath.getSqrtPriceAtTick(vault.tickLower()),
                TickMath.getSqrtPriceAtTick(vault.tickUpper()),
                vault.positionLiquidity()
            );
            holdings += LiquidityLib.valueInToken0(p0, p1, sqrtP);
        }

        uint256 pending = LiquidityLib.valueInToken0(vault.pendingFees0(), vault.pendingFees1(), sqrtP);
        uint256 nav = vault.totalAssetsValue();
        // LP NAV plus curator fees must be backed by real holdings (rounding-tolerant).
        assertLe(nav + pending, holdings + 1, "nav + pending fees must be backed by holdings");

        // Curator fees are always claimable from idle balances.
        assertGe(idle0, vault.pendingFees0(), "pending fee0 not backed by idle tokens");
        assertGe(idle1, vault.pendingFees1(), "pending fee1 not backed by idle tokens");

        // No over-redemption: the sum of every holder's pro-rata claim cannot exceed LP NAV.
        uint256 supply = vault.totalSupply();
        if (supply > 0) {
            uint256 sumClaims;
            for (uint256 i = 0; i < actors.length; i++) {
                sumClaims += MathLib.mulDivDown(nav, vault.balanceOf(actors[i]), supply);
            }
            assertLe(sumClaims, nav, "holders cannot collectively redeem more than NAV");
        }
    }
}
