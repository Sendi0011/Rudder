// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";

/// @title VaultFactory
/// @notice Creates minimal-proxy vault clones; vaults call PoolManager.unlock directly
contract VaultFactory {
    using Clones for address;

    event VaultCreated(address indexed vault, uint256 indexed strategyId, PoolKey poolKey);

    address public immutable vaultImplementation;
    IPoolManager public immutable poolManager;

    mapping(address => uint256) public vaultToStrategyId;

    constructor(address _vaultImplementation, IPoolManager _manager) {
        vaultImplementation = _vaultImplementation;
        poolManager = _manager;
    }

    function createVault(uint256 strategyId, PoolKey calldata poolKey) external returns (address vault) {
        vault = vaultImplementation.clone();
        vaultToStrategyId[vault] = strategyId;
        // Initialize vault (T4 will add init interface)
        emit VaultCreated(vault, strategyId, poolKey);
    }

    function isVault(address who) external view returns (bool) {
        return vaultToStrategyId[who] != 0;
    }
}
