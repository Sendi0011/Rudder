// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

/// @title RudderHook
contract RudderHook is IHooks, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error OnlyVault();
    error Paused();

    struct Observation {
        uint32 timestamp;
        uint160 sqrtPriceX96;
    }

    uint256 public constant MIN_OBSERVATIONS = 2;
    uint256 public constant MAX_OBSERVATION_AGE = 1 hours;

    mapping(PoolId => Observation[]) internal _observations;

    IPoolManager public immutable poolManager;
    address public immutable vaultFactory;
    bool public paused;

    constructor(IPoolManager _manager, address _vaultFactory) {
        poolManager = _manager;
        vaultFactory = _vaultFactory;
        Hooks.validateHookPermissions(this, getHookPermissions());
    }

    function setPaused(bool _paused) external {
        paused = _paused;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert();
        _;
    }

    function _getVault() internal view returns (address) {
        return vaultFactory;
    }

    function isOracleReady(PoolKey calldata key) public view returns (bool) {
        PoolId id = key.toId();
        Observation[] storage obs = _observations[id];
        if (obs.length < MIN_OBSERVATIONS) return false;
        Observation storage last = obs[obs.length - 1];
        if (block.timestamp - last.timestamp > MAX_OBSERVATION_AGE) return false;
        return true;
    }

    function getLastObservation(PoolKey calldata key) external view returns (uint32 ts, uint160 sqrtPriceX96) {
        PoolId id = key.toId();
        Observation[] storage obs = _observations[id];
        if (obs.length == 0) return (0, 0);
        Observation storage last = obs[obs.length - 1];
        return (last.timestamp, last.sqrtPriceX96);
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        if (sender != _getVault()) revert OnlyVault();
        if (paused) revert Paused();
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        Observation[] storage obs = _observations[id];
        if (obs.length == 0 || (block.timestamp != obs[obs.length - 1].timestamp)) {
            obs.push(Observation({timestamp: uint32(block.timestamp), sqrtPriceX96: sqrtPriceX96}));
            if (obs.length > 1440) {
                for (uint256 i = 0; i < 720; i++) {
                    obs[i] = obs[i + 720];
                }
                assembly {
                    sstore(obs.slot, sub(mload(obs.slot), 720))
                }
            }
        }
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterDonate.selector;
    }
}
