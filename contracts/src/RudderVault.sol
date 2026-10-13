// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title RudderVault
/// @notice ERC-20 vault clone; per-account hold basket (amount0,amount1) stored only. Valuation at withdrawal.
/// @dev Exit always works (pause blocks deposits/rebalances only; never withdrawals) - enforced by callers.
contract RudderVault is ERC20, ReentrancyGuard {
    struct Basket {
        uint256 amount0;
        uint256 amount1;
    }

    IPoolManager public poolManager;
    address public factory;
    uint256 public strategyId;
    PoolKey public poolKey;
    bool public initialized;

    mapping(address => Basket) public holdBasket;

    constructor() ERC20("Rudder Vault Share", "RVS") {}

    function initialize(address _poolManager, address _factory, uint256 _strategyId, PoolKey calldata _poolKey)
        external
    {
        require(!initialized, "already initialized");
        poolManager = IPoolManager(_poolManager);
        factory = _factory;
        strategyId = _strategyId;
        poolKey = _poolKey;
        initialized = true;
    }

    // Deposit/withdraw/migrate/rebalance skeletons for T4-T7
}
