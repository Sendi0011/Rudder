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

    mapping(address => Basket) public holdBasket;

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

    /// @dev Deposits require a ready oracle, EXCEPT the very first deposit that bootstraps the pool
    ///      (a TWAP cannot exist before there is liquidity to swap against).
    modifier depositOracle() {
        if (totalSupply() > 0 && !IRudderHook(hook).isOracleReady(poolKey)) revert OracleBad();
        _;
    }

    /// @dev Rebalances require a ready oracle, except the initial range-set that bootstraps the position.
    modifier rebalanceOracle() {
        if (rangeSet && !IRudderHook(hook).isOracleReady(poolKey)) revert OracleBad();
        _;
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

        uint256 idle0 = _idle0();
        uint256 idle1 = _idle1();
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
        (uint256 fee0, uint256 fee1) = _performanceFee(hb, total0, total1);
        amount0Out = total0 - fee0;
        amount1Out = total1 - fee1;

        _burn(msg.sender, shares);
        holdBasket[msg.sender].amount0 = hb.amount0 - MathLib.mulDivDown(hb.amount0, shares, userShares);
        holdBasket[msg.sender].amount1 = hb.amount1 - MathLib.mulDivDown(hb.amount1, shares, userShares);

        if (amount0Out > 0) IERC20(Currency.unwrap(poolKey.currency0)).transfer(recipient, amount0Out);
        if (amount1Out > 0) IERC20(Currency.unwrap(poolKey.currency1)).transfer(recipient, amount1Out);
        if (fee0 > 0) IERC20(Currency.unwrap(poolKey.currency0)).transfer(feeRecipient, fee0);
        if (fee1 > 0) IERC20(Currency.unwrap(poolKey.currency1)).transfer(feeRecipient, fee1);

        emit Withdraw(msg.sender, recipient, shares, amount0Out, amount1Out, fee0, fee1);
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
        liquidity = LiquidityLib.getLiquidityForAmounts(sqrtP, sqrtA, sqrtB, _idle0(), _idle1());
        if (liquidity > 0) {
            _addLiquidity(liquidity);
            positionLiquidity += liquidity;
        }
    }

    // ---------------------------------------------------------------------
    // Valuation and fee
    // ---------------------------------------------------------------------

    /// @notice Total vault value denominated in token0 at the TWAP price (idle + position).
    function totalAssetsValue() external view returns (uint256) {
        return _totalAssetsValue();
    }

    function _totalAssetsValue() internal view returns (uint256 value0) {
        uint160 sqrtP = _twapSqrtPrice();
        value0 = LiquidityLib.valueInToken0(_idle0(), _idle1(), sqrtP);
        if (positionLiquidity > 0) {
            (uint256 p0, uint256 p1) = _positionAmounts(sqrtP);
            value0 += LiquidityLib.valueInToken0(p0, p1, sqrtP);
        }
    }

    function _positionAmounts(uint160 sqrtP) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        return LiquidityLib.getAmountsForLiquidity(sqrtP, sqrtA, sqrtB, positionLiquidity);
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
