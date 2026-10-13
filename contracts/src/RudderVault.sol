// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {NAVMath} from "./libraries/NAVMath.sol";
import {Envelope, EnvelopeLib} from "./libraries/EnvelopeLib.sol";

interface IRudderHook {
    function isOracleReady(PoolKey calldata key) external view returns (bool);
    function paused() external view returns (bool);
}

interface IStrategyRegistry {
    function getEnvelope(uint256 id) external view returns (Envelope memory);
    function isCurator(uint256 id, address who) external view returns (bool);
}

/// @title RudderVault
contract RudderVault is ERC20, ReentrancyGuard {
    using NAVMath for NAVMath.Basket;

    error InvalidInit();
    error Paused();
    error AlreadyInitialized();
    error OracleBad();
    error ZeroAmount();
    error InsufficientBalance();
    error MinLiquidityLocked();
    error NotCurator();
    error RebalanceOutOfBounds();

    struct Basket {
        uint256 amount0;
        uint256 amount1;
    }

    IPoolManager public poolManager;
    address public factory;
    address public hook;
    address public registry;
    uint256 public strategyId;
    PoolKey public poolKey;
    bool public initialized;

    mapping(address => Basket) public holdBasket;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public constant PROTOCOL_MAX_FEE_BPS = 2000;
    uint256 public constant PERFORMANCE_FEE_BPS = 1000;
    uint256 public lastRebalanceTimestamp;

    constructor() ERC20("Rudder Vault Share", "RVS") {}

    function initialize(
        address _poolManager,
        address _factory,
        address _hook,
        address _registry,
        uint256 _strategyId,
        PoolKey calldata _poolKey
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (_poolManager == address(0) || _factory == address(0) || _hook == address(0) || _registry == address(0)) {
            revert InvalidInit();
        }
        poolManager = IPoolManager(_poolManager);
        factory = _factory;
        hook = _hook;
        registry = _registry;
        strategyId = _strategyId;
        poolKey = _poolKey;
        initialized = true;
        lastRebalanceTimestamp = uint48(block.timestamp);
    }

    modifier whenNotPaused() {
        if (IRudderHook(hook).paused()) revert Paused();
        _;
    }

    modifier oracleOk() {
        if (!IRudderHook(hook).isOracleReady(poolKey)) revert OracleBad();
        _;
    }

    modifier onlyCurator() {
        if (!IStrategyRegistry(registry).isCurator(strategyId, msg.sender)) revert NotCurator();
        _;
    }

    function deposit(uint256 amount0, uint256 amount1, address recipient)
        external
        nonReentrant
        whenNotPaused
        oracleOk
        returns (uint256 shares)
    {
        if (amount0 == 0 && amount1 == 0) revert ZeroAmount();
        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = amount0 + amount1;
            if (shares < MINIMUM_LIQUIDITY) revert MinLiquidityLocked();
        } else {
            uint256 totalAssetsVal = amount0 + amount1 + _totalAssetsValue();
            shares = MathLib.mulDivDown(amount0 + amount1, supply, totalAssetsVal);
        }
        _mint(recipient, shares);
        holdBasket[recipient] = Basket({
            amount0: holdBasket[recipient].amount0 + amount0, amount1: holdBasket[recipient].amount1 + amount1
        });
    }

    function withdraw(uint256 shares, address recipient)
        external
        nonReentrant
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientBalance();
        uint256 supply = totalSupply();
        Basket memory userHold = holdBasket[msg.sender];
        NAVMath.Basket memory totalHold = NAVMath.Basket({amount0: _getTotalHold0(), amount1: _getTotalHold1()});
        NAVMath.Basket memory outFromHold = NAVMath.proportionalBasket(totalHold, shares, supply);
        holdBasket[msg.sender] =
            Basket({amount0: userHold.amount0 - outFromHold.amount0, amount1: userHold.amount1 - outFromHold.amount1});
        amount0Out = outFromHold.amount0;
        amount1Out = outFromHold.amount1;

        // Oracle-safe: zero fee if not ready (spec). Fee crystallized at withdrawal, capped by PROTOCOL_MAX_FEE_BPS
        if (IRudderHook(hook).isOracleReady(poolKey)) {
            uint256 depositorValue = amount0Out + amount1Out;
            uint256 holdValue = userHold.amount0 + userHold.amount1;
            uint256 gain = depositorValue > holdValue ? depositorValue - holdValue : 0;
            if (gain > 0) {
                uint256 feeBps = PERFORMANCE_FEE_BPS > PROTOCOL_MAX_FEE_BPS ? PROTOCOL_MAX_FEE_BPS : PERFORMANCE_FEE_BPS;
                uint256 feeAmount = MathLib.mulDivDown(gain, feeBps, 10000);
                if (feeAmount > 0) {
                    uint256 feeReduction = MathLib.mulDivDown(shares, feeAmount, depositorValue);
                    // Reduce amounts proportionally to reflect fee (round down, favor vault)
                    uint256 fee0 = MathLib.mulDivDown(amount0Out, feeAmount, depositorValue);
                    uint256 fee1 = MathLib.mulDivDown(amount1Out, feeAmount, depositorValue);
                    amount0Out = MathLib.subFloor(amount0Out, fee0);
                    amount1Out = MathLib.subFloor(amount1Out, fee1);
                    // Burn fee shares conceptually - fee stays in vault; simplification for scaffold
                    _burn(msg.sender, shares - feeReduction > shares ? 0 : shares - feeReduction);
                    return (amount0Out, amount1Out);
                }
            }
        }
        _burn(msg.sender, shares);
    }

    function rebalance(int24 newTickLower, int24 newTickUpper, uint32 priceImpactBps, int24 navLossBps)
        external
        nonReentrant
        whenNotPaused
        oracleOk
        onlyCurator
    {
        Envelope memory env = IStrategyRegistry(registry).getEnvelope(strategyId);
        int24 width = newTickUpper - newTickLower;
        EnvelopeLib.validateRangeWidth(width, env.maxRangeWidth);
        EnvelopeLib.validateInterval(uint48(lastRebalanceTimestamp), uint48(block.timestamp), env.minRebalanceInterval);
        EnvelopeLib.validatePriceImpact(priceImpactBps, env.maxPriceImpactBps);
        EnvelopeLib.validateNavLoss(navLossBps, env.maxNavLossBps);
        lastRebalanceTimestamp = uint48(block.timestamp);
    }

    function _getTotalHold0() internal view returns (uint256) {
        return 0;
    }

    function _getTotalHold1() internal view returns (uint256) {
        return 0;
    }

    function _totalAssetsValue() internal view returns (uint256) {
        return 0;
    }
}
