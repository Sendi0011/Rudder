// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {LiquidityLib} from "./libraries/LiquidityLib.sol";
import {Envelope, EnvelopeLib} from "./libraries/EnvelopeLib.sol";

interface IRudderHook {
    function isOracleReady(PoolKey calldata key) external view returns (bool);
    function paused() external view returns (bool);
    function consult(PoolKey calldata key, uint32 secondsAgo) external view returns (uint160 sqrtPriceX96);
}

interface IStrategyRegistry {
    function getEnvelope(uint256 id) external view returns (Envelope memory);
    function isCurator(uint256 id, address who) external view returns (bool);
    function checkpointAlpha(uint256 id, int256 cumulativeAlpha) external;
}

/// @title RudderVault
/// @notice Curated liquidity vault. Deployed as a minimal-proxy clone by VaultFactory and initialized
///         in the same transaction as cloning; the bare implementation is locked via `_disableInitializers`.
///         Holds one v4 position plus idle balances; withdrawals always pay out pro-rata and never revert
///         on a bad oracle (fee is simply zero in that case).
contract RudderVault is Initializable, ERC20, ReentrancyGuard, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    error InvalidInit();
    error Paused();
    error OracleBad();
    error ZeroAmount();
    error InsufficientBalance();
    error MinLiquidityLocked();
    error NotCurator();
    error RebalanceOutOfBounds();
    error TickNotAligned();
    error FeeOnTransferUnsupported();
    error NotPoolManager();
    error TokenNotERC20();
    error SettlementMismatch();
    error SpotTwapDeviation();

    struct Basket {
        uint256 amount0;
        uint256 amount1;
    }

    uint8 internal constant ACTION_COLLECT = 0;
    uint8 internal constant ACTION_ADD = 1;
    uint8 internal constant ACTION_REMOVE = 2;

    /// @notice TWAP window (seconds) used for all valuation.
    uint32 public constant TWAP_WINDOW = 1800;

    IPoolManager public poolManager;
    address public factory;
    address public hook;
    address public registry;
    uint256 public strategyId;
    address public curator;
    address public feeRecipient;
    PoolKey public poolKey;

    /// @notice Performance fee in bps, clamped to PROTOCOL_MAX_FEE_BPS at init.
    uint16 public feeCapBps;

    /// @notice Envelope captured at creation (reference only); live enforcement reads the registry.
    Envelope public initialEnvelope;

    /// @notice The vault's single position.
    int24 public tickLower;
    int24 public tickUpper;
    uint128 public positionLiquidity;
    bool public rangeSet;
    /// @notice One-time flag marking the end of the oracle-bootstrap phase. While false, the
    ///         oracle-readiness requirement is waived for deposit/rebalance. Once true, it remains
    ///         true forever and operations require the TWAP ring buffer to be ready.
    bool public oracleBootstrapped;

    mapping(address => Basket) public holdBasket;

    /// @notice Aggregate hold basket (sum of deposits, reduced pro-rata on withdraw). The vault-level
    ///         hold benchmark used for alpha checkpoints.
    Basket public totalHold;

    /// @notice Cumulative alpha reported to the registry: the running sum of per-interval
    ///         `vaultReturn - holdReturn`, each a 1e18-scaled fraction. Dimensionless, so vaults of
    ///         any size and token decimals are ranked on the same scale.
    int256 public cumulativeAlpha;

    /// @notice Baseline for the next interval, captured at TWAP after the last action: NAV per 1e18
    ///         shares, the hold basket per 1e18 shares, and that basket's token0 value. Rebasing after
    ///         every action keeps deposits and withdrawals out of the measured return.
    uint256 public baseNavPerShare;
    uint256 public baseHold0PerShare;
    uint256 public baseHold1PerShare;
    uint256 public baseHoldValuePerShare;

    /// @notice Curator fees accrued but not yet claimed (pull-based). Kept in-vault and excluded from
    ///         NAV, so a fee recipient that rejects transfers can never block a withdrawal.
    uint256 public pendingFees0;
    uint256 public pendingFees1;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public constant PROTOCOL_MAX_FEE_BPS = 2000;
    /// @notice Protocol-wide ceiling on the spot-vs-TWAP deviation a deposit may be priced at, applied
    ///         on top of the strategy envelope. A curator cannot loosen it by widening the envelope.
    uint32 public constant PROTOCOL_MAX_PRICE_IMPACT_BPS = 500;
    uint256 public lastRebalanceTimestamp;

    event Deposit(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed recipient,
        uint256 shares,
        uint256 amount0,
        uint256 amount1,
        uint256 fee0,
        uint256 fee1
    );
    event Rebalance(uint256 indexed strategyId, int24 tickLower, int24 tickUpper, uint128 liquidity);
    event FeesClaimed(address indexed recipient, uint256 amount0, uint256 amount1);

    /// @dev Clone metadata cannot be written by the implementation constructor, so name/symbol are fixed.
    constructor() ERC20("Rudder Vault Share", "RVS") {
        _disableInitializers();
    }

    function name() public pure override returns (string memory) {
        return "Rudder Vault Share";
    }

    function symbol() public pure override returns (string memory) {
        return "RVS";
    }

    /// @notice One-time initializer, called by VaultFactory in the same tx as cloning.
    function initialize(
        address _poolManager,
        address _factory,
        address _registry,
        uint256 _strategyId,
        address _curator,
        uint16 _feeCapBps,
        PoolKey calldata _poolKey,
        Envelope calldata _envelope
    ) external initializer {
        if (_poolManager == address(0) || _factory == address(0) || _registry == address(0)) {
            revert InvalidInit();
        }
        if (_curator == address(0) || address(_poolKey.hooks) == address(0)) revert InvalidInit();
        if (Currency.unwrap(_poolKey.currency0) == address(0) || Currency.unwrap(_poolKey.currency1) == address(0)) {
            revert TokenNotERC20();
        }
        poolManager = IPoolManager(_poolManager);
        factory = _factory;
        registry = _registry;
        strategyId = _strategyId;
        curator = _curator;
        feeRecipient = _curator;
        hook = address(_poolKey.hooks);
        poolKey = _poolKey;
        feeCapBps = _feeCapBps > PROTOCOL_MAX_FEE_BPS ? uint16(PROTOCOL_MAX_FEE_BPS) : _feeCapBps;
        initialEnvelope = _envelope;
        lastRebalanceTimestamp = uint48(block.timestamp);
    }

    modifier whenNotPaused() {
        if (IRudderHook(hook).paused()) revert Paused();
        _;
    }

    /// @dev Deposits require a ready oracle once bootstrapped. Bootstrap is controlled by a
    ///      one-time flag (not totalSupply) to prevent reopening after emptying the vault.
    modifier depositOracle() {
        _syncBootstrap();
        if (oracleBootstrapped && !IRudderHook(hook).isOracleReady(poolKey)) revert OracleBad();
        _;
    }

    /// @dev Rebalances require a ready oracle once bootstrapped.
    modifier rebalanceOracle() {
        _syncBootstrap();
        if (oracleBootstrapped && !IRudderHook(hook).isOracleReady(poolKey)) revert OracleBad();
        _;
    }

    /// @dev Closes the one-time bootstrap exemption as soon as the TWAP is ready. The flag is
    ///      one-way: emptying the vault (or the vault going dormant) can never reopen it.
    function _syncBootstrap() internal {
        if (!oracleBootstrapped && IRudderHook(hook).isOracleReady(poolKey)) {
            oracleBootstrapped = true;
        }
    }

    modifier onlyCurator() {
        if (!IStrategyRegistry(registry).isCurator(strategyId, msg.sender)) revert NotCurator();
        _;
    }

    // ---------------------------------------------------------------------
    // LP actions
    // ---------------------------------------------------------------------

    function deposit(uint256 amount0, uint256 amount1, address recipient)
        external
        nonReentrant
        whenNotPaused
        depositOracle
        returns (uint256 shares)
    {
        if (amount0 == 0 && amount1 == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAmount();

        _accrueAlphaInterval();

        // Reject deposits priced off a manipulated spot: once the TWAP is live, the spot must stay
        // within the tighter of the envelope's deviation bound and the protocol ceiling. Withdrawals
        // are never gated by this.
        if (oracleBootstrapped) {
            Envelope memory env = IStrategyRegistry(registry).getEnvelope(strategyId);
            uint32 cap = env.maxPriceImpactBps < PROTOCOL_MAX_PRICE_IMPACT_BPS
                ? env.maxPriceImpactBps
                : PROTOCOL_MAX_PRICE_IMPACT_BPS;
            if (_priceImpactBps(_spotSqrtPrice(), _twapSqrtPrice()) > cap) revert SpotTwapDeviation();
        }

        if (positionLiquidity > 0) _collect();

        uint160 sqrtP = _twapSqrtPrice();
        uint256 preValue0 = _totalAssetsValue();

        uint256 b0 = _idle0();
        uint256 b1 = _idle1();
        if (amount0 > 0) _pull(poolKey.currency0, msg.sender, amount0);
        if (amount1 > 0) _pull(poolKey.currency1, msg.sender, amount1);
        if (_idle0() - b0 != amount0 || _idle1() - b1 != amount1) revert FeeOnTransferUnsupported();

        uint256 depositValue0 = LiquidityLib.valueInToken0(amount0, amount1, sqrtP);
        uint256 supply = totalSupply();
        if (supply == 0) {
            if (depositValue0 < MINIMUM_LIQUIDITY) revert MinLiquidityLocked();
            _mint(address(this), MINIMUM_LIQUIDITY);
            shares = depositValue0 - MINIMUM_LIQUIDITY;
        } else {
            shares = preValue0 == 0 ? depositValue0 : _mulDiv(depositValue0, supply, preValue0);
        }
        if (shares == 0) revert ZeroAmount();

        if (rangeSet) _addLiquidityFromIdle(_spotSqrtPrice());

        _mint(recipient, shares);
        Basket storage hb = holdBasket[recipient];
        hb.amount0 += amount0;
        hb.amount1 += amount1;
        totalHold.amount0 += amount0;
        totalHold.amount1 += amount1;
        _rebaseAlphaBaseline();
        emit Deposit(msg.sender, recipient, amount0, amount1, shares);
    }

    function withdraw(uint256 shares, address recipient)
        external
        nonReentrant
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        if (shares == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAmount();
        uint256 userShares = balanceOf(msg.sender);
        if (userShares < shares) revert InsufficientBalance();
        uint256 supply = totalSupply();

        _accrueAlphaInterval();

        if (positionLiquidity > 0) _collect();

        uint256 idle0 = _freeIdle0();
        uint256 idle1 = _freeIdle1();
        uint256 removed0;
        uint256 removed1;
        if (positionLiquidity > 0) {
            uint128 lRemove = uint128(_mulDiv(uint256(positionLiquidity), shares, supply));
            if (lRemove > 0) {
                (removed0, removed1) = _removeLiquidity(lRemove, address(this));
                positionLiquidity -= lRemove;
            }
        }

        uint256 total0 = removed0 + _mulDiv(idle0, shares, supply);
        uint256 total1 = removed1 + _mulDiv(idle1, shares, supply);

        Basket memory hb = holdBasket[msg.sender];
        // The hold benchmark is compared like-for-like: pro-rate the account's basket to the shares
        // being redeemed, so partial withdrawals are charged fairly (not deferred to a full exit).
        uint256 hb0 = _mulDiv(hb.amount0, shares, userShares);
        uint256 hb1 = _mulDiv(hb.amount1, shares, userShares);
        (uint256 fee0, uint256 fee1) = _performanceFee(Basket({amount0: hb0, amount1: hb1}), total0, total1);
        amount0Out = total0 - fee0;
        amount1Out = total1 - fee1;

        _burn(msg.sender, shares);
        holdBasket[msg.sender].amount0 = hb.amount0 - hb0;
        holdBasket[msg.sender].amount1 = hb.amount1 - hb1;
        totalHold.amount0 -= _mulDiv(totalHold.amount0, shares, supply);
        totalHold.amount1 -= _mulDiv(totalHold.amount1, shares, supply);

        if (amount0Out > 0) IERC20(Currency.unwrap(poolKey.currency0)).safeTransfer(recipient, amount0Out);
        if (amount1Out > 0) IERC20(Currency.unwrap(poolKey.currency1)).safeTransfer(recipient, amount1Out);
        // Fees are accrued for pull-claim; the transfer is never attempted during a withdrawal.
        pendingFees0 += fee0;
        pendingFees1 += fee1;

        _rebaseAlphaBaseline();
        emit Withdraw(msg.sender, recipient, shares, amount0Out, amount1Out, fee0, fee1);
    }

    /// @notice Claim accrued curator fees (pull-based). A fee recipient that rejects transfers only
    ///         blocks its own claim, never an LP withdrawal.
    function claimFees() external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (msg.sender != feeRecipient) revert NotCurator();
        amount0 = pendingFees0;
        amount1 = pendingFees1;
        pendingFees0 = 0;
        pendingFees1 = 0;
        if (amount0 > 0) IERC20(Currency.unwrap(poolKey.currency0)).safeTransfer(feeRecipient, amount0);
        if (amount1 > 0) IERC20(Currency.unwrap(poolKey.currency1)).safeTransfer(feeRecipient, amount1);
        emit FeesClaimed(feeRecipient, amount0, amount1);
    }

    /// @notice Move the position within the envelope. Metrics are measured on-chain (never trusted
    ///         from the caller): center shift vs prior range, price impact vs TWAP, NAV before/after.
    function rebalance(int24 newTickLower, int24 newTickUpper)
        external
        nonReentrant
        whenNotPaused
        rebalanceOracle
        onlyCurator
    {
        Envelope memory env = IStrategyRegistry(registry).getEnvelope(strategyId);

        int24 spacing = poolKey.tickSpacing;
        if (spacing <= 0) revert RebalanceOutOfBounds();
        if (newTickLower % spacing != 0 || newTickUpper % spacing != 0) revert TickNotAligned();
        if (newTickLower >= newTickUpper) revert RebalanceOutOfBounds();
        if (newTickLower < TickMath.minUsableTick(spacing) || newTickUpper > TickMath.maxUsableTick(spacing)) {
            revert RebalanceOutOfBounds();
        }

        int24 width = newTickUpper - newTickLower;
        EnvelopeLib.validateRangeWidth(width, env.maxRangeWidth);

        int24 newCenter = (newTickLower + newTickUpper) / 2;
        uint160 spot = _spotSqrtPrice();
        uint160 twap = _twapSqrtPrice();

        // The range centre may never drift further from the TWAP tick than the envelope allows, so
        // liquidity cannot be parked in a regime disconnected from the oracle price.
        EnvelopeLib.validateTwapDistance(newCenter, TickMath.getTickAtSqrtPrice(twap), env.maxTwapDistanceTicks);

        if (rangeSet) {
            EnvelopeLib.validateInterval(
                uint48(lastRebalanceTimestamp), uint48(block.timestamp), env.minRebalanceInterval
            );
            int24 oldCenter = (tickLower + tickUpper) / 2;
            EnvelopeLib.validateCenterShift(newCenter - oldCenter, env.maxCenterShift);
        }

        EnvelopeLib.validatePriceImpact(_priceImpactBps(spot, twap), env.maxPriceImpactBps);

        _accrueAlphaInterval();

        if (positionLiquidity > 0) _collect();
        uint256 preNav = _totalAssetsValue();

        if (positionLiquidity > 0) {
            _removeLiquidity(positionLiquidity, address(this));
            positionLiquidity = 0;
        }
        tickLower = newTickLower;
        tickUpper = newTickUpper;
        rangeSet = true;
        _addLiquidityFromIdle(_spotSqrtPrice());

        uint256 postNav = _totalAssetsValue();
        EnvelopeLib.validateNavLoss(_navLossBps(preNav, postNav), env.maxNavLossBps);

        lastRebalanceTimestamp = uint48(block.timestamp);
        _rebaseAlphaBaseline();
        emit Rebalance(strategyId, newTickLower, newTickUpper, positionLiquidity);
    }

    // ---------------------------------------------------------------------
    // v4 unlock plumbing
    // ---------------------------------------------------------------------

    /// @dev Only ever called by the PoolManager during `unlock`.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (uint8 action, int24 lo, int24 hi, uint128 liquidity, address recipient) =
            abi.decode(data, (uint8, int24, int24, uint128, address));

        int256 liquidityDelta;
        if (action == ACTION_ADD) {
            liquidityDelta = int256(uint256(liquidity));
        } else if (action == ACTION_REMOVE) {
            liquidityDelta = -int256(uint256(liquidity));
        }

        (BalanceDelta callerDelta,) = poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: lo, tickUpper: hi, liquidityDelta: liquidityDelta, salt: bytes32(0)}),
            ""
        );
        _settleDelta(callerDelta, recipient);
        return abi.encodePacked(callerDelta);
    }

    function _settleDelta(BalanceDelta delta, address recipient) internal {
        _settleCurrency(poolKey.currency0, delta.amount0(), recipient);
        _settleCurrency(poolKey.currency1, delta.amount1(), recipient);
    }

    function _settleCurrency(Currency currency, int128 d, address recipient) internal {
        if (d < 0) {
            uint256 owed = uint256(-int256(d));
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), owed);
            poolManager.settle();
        } else if (d > 0) {
            poolManager.take(currency, recipient, uint256(int256(d)));
        }
    }

    function _collect() internal {
        poolManager.unlock(abi.encode(ACTION_COLLECT, tickLower, tickUpper, uint128(0), address(this)));
    }

    function _addLiquidity(uint128 liquidity) internal {
        poolManager.unlock(abi.encode(ACTION_ADD, tickLower, tickUpper, liquidity, address(this)));
    }

    function _removeLiquidity(uint128 liquidity, address recipient)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        bytes memory ret = poolManager.unlock(abi.encode(ACTION_REMOVE, tickLower, tickUpper, liquidity, recipient));
        BalanceDelta delta = abi.decode(ret, (BalanceDelta));
        amount0 = uint256(int256(delta.amount0()));
        amount1 = uint256(int256(delta.amount1()));
    }

    function _addLiquidityFromIdle(uint160 sqrtP) internal returns (uint128 liquidity) {
        int24 lo = tickLower;
        int24 hi = tickUpper;
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(lo);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(hi);
        // Only deploy LP-owned idle; pending curator fees stay liquid and claimable.
        liquidity = LiquidityLib.getLiquidityForAmounts(sqrtP, sqrtA, sqrtB, _freeIdle0(), _freeIdle1());
        if (liquidity > 0) {
            _addLiquidity(liquidity);
            positionLiquidity += liquidity;
        }
    }

    function _freeIdle0() internal view returns (uint256) {
        uint256 b = _idle0();
        return b > pendingFees0 ? b - pendingFees0 : 0;
    }

    function _freeIdle1() internal view returns (uint256) {
        uint256 b = _idle1();
        return b > pendingFees1 ? b - pendingFees1 : 0;
    }

    // ---------------------------------------------------------------------
    // Valuation and fee
    // ---------------------------------------------------------------------

    /// @notice Total vault value denominated in token0 at the TWAP price (idle + position).
    function totalAssetsValue() external view returns (uint256) {
        return _totalAssetsValue();
    }

    /// @notice The TWAP sqrt price this vault values assets at (falls back to spot if untracked).
    function twapSqrtPrice() external view returns (uint160) {
        return _twapSqrtPrice();
    }

    /// @notice ERC-20 address of the pool's token0 (for integrators such as the migrator).
    function currency0() external view returns (address) {
        return Currency.unwrap(poolKey.currency0);
    }

    /// @notice ERC-20 address of the pool's token1 (for integrators such as the migrator).
    function currency1() external view returns (address) {
        return Currency.unwrap(poolKey.currency1);
    }

    function _totalAssetsValue() internal view returns (uint256 value0) {
        uint160 sqrtP = _twapSqrtPrice();
        value0 = LiquidityLib.valueInToken0(_idle0(), _idle1(), sqrtP);
        if (positionLiquidity > 0) {
            (uint256 p0, uint256 p1) = _positionAmounts(sqrtP);
            value0 += LiquidityLib.valueInToken0(p0, p1, sqrtP);
        }
        // Pending curator fees are a liability: exclude them from LP-owned NAV.
        uint256 liability = LiquidityLib.valueInToken0(pendingFees0, pendingFees1, sqrtP);
        value0 = value0 > liability ? value0 - liability : 0;
    }

    function _positionAmounts(uint160 sqrtP) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        return LiquidityLib.getAmountsForLiquidity(sqrtP, sqrtA, sqrtB, positionLiquidity);
    }

    /// @dev Accrues the alpha earned since the last baseline, BEFORE the current action changes any
    ///      balances. Alpha is the vault's per-share return minus the return of simply holding the
    ///      baseline basket, both valued at TWAP and expressed as 1e18-scaled fractions. The interval
    ///      is added to a running accumulator so the registry ranks dimensionless scores. Skipped until
    ///      a baseline exists (first action) or while the oracle is not ready.
    function _accrueAlphaInterval() internal {
        if (baseNavPerShare == 0) return;
        if (!IRudderHook(hook).isOracleReady(poolKey)) return;
        uint256 supply = totalSupply();
        if (supply == 0) return;
        uint160 sqrtP = _twapSqrtPrice();
        uint256 navPerShareNow = _mulDiv(_totalAssetsValue(), 1e18, supply);
        int256 vaultReturn = int256(_mulDiv(navPerShareNow, 1e18, baseNavPerShare)) - int256(1e18);
        int256 holdReturn;
        if (baseHoldValuePerShare > 0) {
            uint256 holdNow = LiquidityLib.valueInToken0(baseHold0PerShare, baseHold1PerShare, sqrtP);
            holdReturn = int256(_mulDiv(holdNow, 1e18, baseHoldValuePerShare)) - int256(1e18);
        }
        cumulativeAlpha += vaultReturn - holdReturn;
        // Best-effort: a registry revert must never block an LP action (a withdrawal in particular);
        // the accumulator is retried on the next action.
        try IStrategyRegistry(registry).checkpointAlpha(strategyId, cumulativeAlpha) {} catch {}
    }

    /// @dev Re-captures the baseline AFTER the action, so the just-deposited or just-withdrawn amounts
    ///      start the next interval rather than counting as performance. While the oracle is not ready
    ///      the baseline is left untouched, so the next interval spans the gap.
    function _rebaseAlphaBaseline() internal {
        if (!IRudderHook(hook).isOracleReady(poolKey)) return;
        uint256 supply = totalSupply();
        if (supply == 0) {
            baseNavPerShare = 0;
            baseHold0PerShare = 0;
            baseHold1PerShare = 0;
            baseHoldValuePerShare = 0;
            return;
        }
        uint160 sqrtP = _twapSqrtPrice();
        baseNavPerShare = _mulDiv(_totalAssetsValue(), 1e18, supply);
        baseHold0PerShare = _mulDiv(totalHold.amount0, 1e18, supply);
        baseHold1PerShare = _mulDiv(totalHold.amount1, 1e18, supply);
        baseHoldValuePerShare = LiquidityLib.valueInToken0(baseHold0PerShare, baseHold1PerShare, sqrtP);
    }

    function _performanceFee(Basket memory hb, uint256 total0, uint256 total1)
        internal
        view
        returns (uint256 fee0, uint256 fee1)
    {
        if (!IRudderHook(hook).isOracleReady(poolKey)) return (0, 0);
        uint160 sqrtP = _twapSqrtPrice();
        uint256 valueOut = LiquidityLib.valueInToken0(total0, total1, sqrtP);
        uint256 holdValue = LiquidityLib.valueInToken0(hb.amount0, hb.amount1, sqrtP);
        if (valueOut == 0 || valueOut <= holdValue) return (0, 0);
        uint256 gain = valueOut - holdValue;
        uint256 feeValue0 = _mulDiv(gain, feeCapBps, 10000);
        if (feeValue0 == 0) return (0, 0);
        fee0 = _mulDiv(total0, feeValue0, valueOut);
        fee1 = _mulDiv(total1, feeValue0, valueOut);
    }

    // ---------------------------------------------------------------------
    // Prices
    // ---------------------------------------------------------------------

    function _spotSqrtPrice() internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
    }

    function _twapSqrtPrice() internal view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = IRudderHook(hook).consult(poolKey, TWAP_WINDOW);
        if (sqrtPriceX96 == 0) sqrtPriceX96 = _spotSqrtPrice();
    }

    /// @dev Deviation of the instantaneous spot price from the TWAP, in basis points of the TWAP.
    ///      This is the vault's manipulation proxy: `maxPriceImpactBps` bounds how far the current
    ///      spot may sit from the oracle price for a rebalance or deposit to be accepted. It measures
    ///      price deviation, not the slippage of any particular trade.
    function _priceImpactBps(uint160 spot, uint160 twap) internal pure returns (uint32) {
        if (twap == 0) return 0;
        uint256 diff = spot > twap ? uint256(spot - twap) : uint256(twap - spot);
        uint256 bps = _mulDiv(diff, 10000, uint256(twap));
        return bps > type(uint32).max ? type(uint32).max : uint32(bps);
    }

    function _navLossBps(uint256 pre, uint256 post) internal pure returns (int24) {
        if (pre == 0 || post >= pre) {
            uint256 gainBps = pre == 0 ? 0 : _mulDiv(post - pre, 10000, pre);
            return gainBps > uint256(uint24(type(int24).max)) ? type(int24).max : int24(int256(gainBps));
        }
        uint256 lossBps = _mulDiv(pre - post, 10000, pre);
        return lossBps > uint256(uint24(type(int24).max)) ? -type(int24).max : -int24(int256(lossBps));
    }

    // ---------------------------------------------------------------------
    // Token helpers
    // ---------------------------------------------------------------------

    function _idle0() internal view returns (uint256) {
        return IERC20(Currency.unwrap(poolKey.currency0)).balanceOf(address(this));
    }

    function _idle1() internal view returns (uint256) {
        return IERC20(Currency.unwrap(poolKey.currency1)).balanceOf(address(this));
    }

    function _pull(Currency currency, address from, uint256 amount) internal {
        IERC20(Currency.unwrap(currency)).safeTransferFrom(from, address(this), amount);
    }

    /// @dev 512-bit fixed-point multiply/divide, rounding down (favors the vault). Never overflows
    ///      on the intermediate product, unlike a naive a*b/denominator.
    function _mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return FullMath.mulDiv(a, b, denominator);
    }

    /// @dev Move the per-account hold benchmark pro-rata with shares on transfer (never on mint or
    ///      burn, which the deposit/withdraw paths account for explicitly). Keeps every holder's
    ///      benchmark attached to the shares it was created for, so a buyer inherits the seller's
    ///      cost basis and the performance fee stays honest across transfers and migrations.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fromBal = balanceOf(from);
            Basket storage hbFrom = holdBasket[from];
            uint256 moved0 = fromBal == 0 ? 0 : _mulDiv(hbFrom.amount0, value, fromBal);
            uint256 moved1 = fromBal == 0 ? 0 : _mulDiv(hbFrom.amount1, value, fromBal);
            hbFrom.amount0 -= moved0;
            hbFrom.amount1 -= moved1;
            Basket storage hbTo = holdBasket[to];
            hbTo.amount0 += moved0;
            hbTo.amount1 += moved1;
        }
        super._update(from, to, value);
    }
}
