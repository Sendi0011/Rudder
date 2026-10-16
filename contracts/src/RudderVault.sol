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
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {MathLib} from "./libraries/MathLib.sol";
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
    function checkpointAlpha(uint256 id, int256 alphaDelta) external;
}

/// @title RudderVault
/// @notice Curated liquidity vault. Deployed as a minimal-proxy clone by VaultFactory and initialized
///         in the same transaction as cloning; the bare implementation is locked via `_disableInitializers`.
///         Holds one v4 position plus idle balances; withdrawals always pay out pro-rata and never revert
///         on a bad oracle (fee is simply zero in that case).
contract RudderVault is Initializable, ERC20, ReentrancyGuard, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

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

    /// @notice NAV-per-share minus hold-value-per-share at the last checkpoint, in token0 wei per 1e18
    ///         shares. Used to emit deltas to the registry.
    int256 public lastAlpha;

    /// @notice Curator fees accrued but not yet claimed (pull-based). Kept in-vault and excluded from
    ///         NAV, so a fee recipient that rejects transfers can never block a withdrawal.
    uint256 public pendingFees0;
    uint256 public pendingFees1;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public constant PROTOCOL_MAX_FEE_BPS = 2000;
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
            shares = preValue0 == 0 ? depositValue0 : MathLib.mulDivDown(depositValue0, supply, preValue0);
        }
        if (shares == 0) revert ZeroAmount();

        if (rangeSet) _addLiquidityFromIdle(_spotSqrtPrice());

        _mint(recipient, shares);
        Basket storage hb = holdBasket[recipient];
        hb.amount0 += amount0;
        hb.amount1 += amount1;
        totalHold.amount0 += amount0;
        totalHold.amount1 += amount1;
        _checkpointAlpha();
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

        if (positionLiquidity > 0) _collect();

        uint256 idle0 = _freeIdle0();
        uint256 idle1 = _freeIdle1();
        uint256 removed0;
        uint256 removed1;
        if (positionLiquidity > 0) {
            uint128 lRemove = uint128(MathLib.mulDivDown(uint256(positionLiquidity), shares, supply));
            if (lRemove > 0) {
                (removed0, removed1) = _removeLiquidity(lRemove, address(this));
                positionLiquidity -= lRemove;
            }
        }

        uint256 total0 = removed0 + MathLib.mulDivDown(idle0, shares, supply);
        uint256 total1 = removed1 + MathLib.mulDivDown(idle1, shares, supply);

        Basket memory hb = holdBasket[msg.sender];
        // The hold benchmark is compared like-for-like: pro-rate the account's basket to the shares
        // being redeemed, so partial withdrawals are charged fairly (not deferred to a full exit).
        uint256 hb0 = MathLib.mulDivDown(hb.amount0, shares, userShares);
        uint256 hb1 = MathLib.mulDivDown(hb.amount1, shares, userShares);
        (uint256 fee0, uint256 fee1) = _performanceFee(Basket({amount0: hb0, amount1: hb1}), total0, total1);
        amount0Out = total0 - fee0;
        amount1Out = total1 - fee1;

        _burn(msg.sender, shares);
        holdBasket[msg.sender].amount0 = hb.amount0 - hb0;
        holdBasket[msg.sender].amount1 = hb.amount1 - hb1;
        totalHold.amount0 -= MathLib.mulDivDown(totalHold.amount0, shares, supply);
        totalHold.amount1 -= MathLib.mulDivDown(totalHold.amount1, shares, supply);

        if (amount0Out > 0) IERC20(Currency.unwrap(poolKey.currency0)).transfer(recipient, amount0Out);
        if (amount1Out > 0) IERC20(Currency.unwrap(poolKey.currency1)).transfer(recipient, amount1Out);
        // Fees are accrued for pull-claim; the transfer is never attempted during a withdrawal.
        pendingFees0 += fee0;
        pendingFees1 += fee1;

        _checkpointAlpha();
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
        if (amount0 > 0) IERC20(Currency.unwrap(poolKey.currency0)).transfer(feeRecipient, amount0);
        if (amount1 > 0) IERC20(Currency.unwrap(poolKey.currency1)).transfer(feeRecipient, amount1);
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

        if (rangeSet) {
            EnvelopeLib.validateInterval(
                uint48(lastRebalanceTimestamp), uint48(block.timestamp), env.minRebalanceInterval
            );
            int24 oldCenter = (tickLower + tickUpper) / 2;
            int24 newCenter = (newTickLower + newTickUpper) / 2;
            EnvelopeLib.validateCenterShift(newCenter - oldCenter, env.maxCenterShift);
        }

        uint160 spot = _spotSqrtPrice();
        uint160 twap = _twapSqrtPrice();
        EnvelopeLib.validatePriceImpact(_priceImpactBps(spot, twap), env.maxPriceImpactBps);

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
        _checkpointAlpha();
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
            if (!IERC20(Currency.unwrap(currency)).transfer(address(poolManager), owed)) {
                revert SettlementMismatch();
            }
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

    /// @notice Current alpha of the vault: NAV-per-share minus hold-value-per-share, both valued at
    ///         TWAP and scaled to 1e18 shares. Positive means the vault beat its hold benchmark.
    function alphaPerShare() external view returns (int256) {
        if (!IRudderHook(hook).isOracleReady(poolKey)) return lastAlpha;
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        uint160 sqrtP = _twapSqrtPrice();
        uint256 nav = _totalAssetsValue();
        uint256 holdValue = LiquidityLib.valueInToken0(totalHold.amount0, totalHold.amount1, sqrtP);
        return int256(MathLib.mulDivDown(nav, 1e18, supply)) - int256(MathLib.mulDivDown(holdValue, 1e18, supply));
    }

    /// @dev Records the change in alpha-vs-hold to the registry. Runs automatically on every
    ///      deposit/withdraw/rebalance (never curator-triggered). Skipped while the oracle is not
    ///      ready, since a checkpoint requires a trustworthy TWAP.
    function _checkpointAlpha() internal {
        if (!IRudderHook(hook).isOracleReady(poolKey)) return;
        uint256 supply = totalSupply();
        if (supply == 0) return;
        uint160 sqrtP = _twapSqrtPrice();
        uint256 nav = _totalAssetsValue();
        uint256 holdValue = LiquidityLib.valueInToken0(totalHold.amount0, totalHold.amount1, sqrtP);
        int256 alpha =
            int256(MathLib.mulDivDown(nav, 1e18, supply)) - int256(MathLib.mulDivDown(holdValue, 1e18, supply));
        // Report the cumulative level; the registry converts a level series into a per-interval score.
        IStrategyRegistry(registry).checkpointAlpha(strategyId, alpha);
        lastAlpha = alpha;
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
        uint256 feeValue0 = MathLib.mulDivDown(gain, feeCapBps, 10000);
        if (feeValue0 == 0) return (0, 0);
        fee0 = MathLib.mulDivDown(total0, feeValue0, valueOut);
        fee1 = MathLib.mulDivDown(total1, feeValue0, valueOut);
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

    function _priceImpactBps(uint160 spot, uint160 twap) internal pure returns (uint32) {
        if (twap == 0) return 0;
        uint256 diff = spot > twap ? uint256(spot - twap) : uint256(twap - spot);
        uint256 bps = MathLib.mulDivDown(diff, 10000, uint256(twap));
        return bps > type(uint32).max ? type(uint32).max : uint32(bps);
    }

    function _navLossBps(uint256 pre, uint256 post) internal pure returns (int24) {
        if (pre == 0 || post >= pre) {
            uint256 gainBps = pre == 0 ? 0 : MathLib.mulDivDown(post - pre, 10000, pre);
            return gainBps > uint256(uint24(type(int24).max)) ? type(int24).max : int24(int256(gainBps));
        }
        uint256 lossBps = MathLib.mulDivDown(pre - post, 10000, pre);
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
        if (!IERC20(Currency.unwrap(currency)).transferFrom(from, address(this), amount)) {
            revert SettlementMismatch();
        }
    }
}
