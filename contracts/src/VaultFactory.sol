// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {Envelope} from "./libraries/EnvelopeLib.sol";

interface IStrategyRegistryView {
    function getCurator(uint256 id) external view returns (address);
    function getEnvelope(uint256 id) external view returns (Envelope memory);
}

interface IRudderVaultInit {
    function initialize(
        address poolManager,
        address factory,
        address registry,
        uint256 strategyId,
        address curator,
        uint16 feeCapBps,
        PoolKey calldata poolKey,
        Envelope calldata envelope
    ) external;
}

/// @title VaultFactory
/// @notice Creates minimal-proxy vault clones and initializes each clone in the same transaction,
///         so a clone can never exist in an uninitialized state. Vaults call PoolManager.unlock
///         directly (no PositionManager NFT).
contract VaultFactory {
    using Clones for address;

    error InvalidImplementation();
    error UnknownStrategy();
    error NotCurator();
    error MissingHook();

    event VaultCreated(address indexed vault, uint256 indexed strategyId, address indexed curator, PoolKey poolKey);

    uint16 public constant PROTOCOL_MAX_FEE_BPS = 2000;

    address public immutable vaultImplementation;
    IPoolManager public immutable poolManager;
    IStrategyRegistryView public immutable registry;

    mapping(address => uint256) public vaultToStrategyId;
    mapping(address => bool) private _isVault;

    /// @notice Number of vaults successfully created.
    uint256 public vaultCount;
    /// @notice All vaults created by this factory, in creation order.
    address[] public vaults;

    constructor(address _vaultImplementation, IPoolManager _manager, address _registry) {
        if (_vaultImplementation == address(0)) revert InvalidImplementation();
        vaultImplementation = _vaultImplementation;
        poolManager = _manager;
        registry = IStrategyRegistryView(_registry);
    }

    /// @notice Deploy and initialize a new vault for `strategyId`. Only the strategy's curator may call.
    /// @dev The clone is initialized within this call; if initialization reverts, the whole tx reverts and
    ///      no uninitialized clone is left behind.
    /// @param strategyId Registered strategy id.
    /// @param poolKey v4 pool key (its `hooks` field is the RudderHook the vault will use).
    /// @param feeCapBps Requested performance fee in bps; clamped by the vault to PROTOCOL_MAX_FEE_BPS.
    /// @return vault The initialized vault clone address.
    function createVault(uint256 strategyId, PoolKey calldata poolKey, uint16 feeCapBps)
        external
        returns (address vault)
    {
        address curator = registry.getCurator(strategyId);
        if (curator == address(0)) revert UnknownStrategy();
        if (msg.sender != curator) revert NotCurator();
        if (address(poolKey.hooks) == address(0)) revert MissingHook();

        Envelope memory envelope = registry.getEnvelope(strategyId);

        vault = vaultImplementation.clone();

        // Mark before initialize so the hook gate (isVault) is consistent even during initialization.
        _isVault[vault] = true;
        vaultToStrategyId[vault] = strategyId;
        vaults.push(vault);
        vaultCount += 1;

        IRudderVaultInit(vault)
            .initialize(
                address(poolManager),
                address(this),
                address(registry),
                strategyId,
                curator,
                feeCapBps,
                poolKey,
                envelope
            );

        emit VaultCreated(vault, strategyId, curator, poolKey);
    }

    /// @notice True if `who` is a vault created by this factory.
    function isVault(address who) external view returns (bool) {
        return _isVault[who];
    }

    /// @notice Length of the vault list (public array getter `vaults(uint256)` exposes elements).
    function vaultsLength() external view returns (uint256) {
        return vaults.length;
    }
}
