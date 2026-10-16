// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";

/// @notice Minimal exact-side router that settles deltas from its own token balance.
contract MiniSwapRouter is IUnlockCallback {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function swap(PoolKey calldata key, bool zeroForOne, int256 amountSpecified, uint160 limit)
        external
        returns (BalanceDelta)
    {
        bytes memory ret = manager.unlock(abi.encode(key, zeroForOne, amountSpecified, limit));
        return abi.decode(ret, (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "not manager");
        (PoolKey memory key, bool zeroForOne, int256 amountSpecified, uint160 limit) =
            abi.decode(data, (PoolKey, bool, int256, uint160));
        BalanceDelta delta = manager.swap(
            key, SwapParams({zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: limit}), ""
        );
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 d) internal {
        if (d < 0) {
            uint256 owed = uint256(-int256(d));
            manager.sync(currency);
            require(IERC20(Currency.unwrap(currency)).transfer(address(manager), owed), "transfer failed");
            manager.settle();
        } else if (d > 0) {
            manager.take(currency, address(this), uint256(int256(d)));
        }
    }
}

/// @title RudderIntegrationBase
/// @notice Real PoolManager + real ERC-20s + a real swap router, so the vault exercises the actual
///         unlock/sync/settle/take flow. Vaults are still created only through VaultFactory.
abstract contract RudderIntegrationBase is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    PoolManager internal manager;
    TestERC20 internal token0;
    TestERC20 internal token1;
    MiniSwapRouter internal router;

    StrategyRegistry internal registry;
    RudderVault internal vaultImpl;
    VaultFactory internal factory;
    RudderHook internal hook;

    PoolKey internal key;
    uint256 internal strategyId;
    address internal curator = address(0xC0FFEE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint160 internal constant SQRT_1_1 = 79228162514264337593543950336; // sqrtPriceX96 at tick 0, price 1:1

    function setUp() public virtual {
        manager = new PoolManager(address(this));
        token0 = new TestERC20(1e30);
        token1 = new TestERC20(1e30);
        // Sort into (currency0, currency1).
        (token0, token1) = address(token0) < address(token1) ? (token0, token1) : (token1, token0);

        router = new MiniSwapRouter(manager);
        IERC20(address(token0)).transfer(address(router), 1e27);
        IERC20(address(token1)).transfer(address(router), 1e27);

        registry = new StrategyRegistry();
        vaultImpl = new RudderVault();
        factory = new VaultFactory(address(vaultImpl), IPoolManager(address(manager)), address(registry));
        hook = _deployMinedHook(IPoolManager(address(manager)), address(this));
        hook.setVaultFactory(address(factory));
        registry.setFactory(address(factory));

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, SQRT_1_1);

        vm.prank(curator);
        strategyId = registry.registerStrategy(_envelope());

        vm.prank(curator);
        vault = RudderVault(factory.createVault(strategyId, key, 1000));

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(curator, "curator");
    }

    RudderVault internal vault;

    function _envelope() internal pure returns (Envelope memory) {
        return Envelope({
            maxRangeWidth: 6000,
            maxCenterShift: 3000,
            maxTwapDistanceTicks: 6000,
            minRebalanceInterval: 1,
            maxPriceImpactBps: 10_000,
            maxNavLossBps: -5000
        });
    }

    function _deployMinedHook(IPoolManager _manager, address _owner) internal returns (RudderHook deployed) {
        bytes memory args = abi.encode(_manager, _owner);
        bytes memory bytecode = abi.encodePacked(type(RudderHook).creationCode, args);
        uint160 requiredFlags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        uint160 flagMask = uint160(0x3FFF);
        bytes32 salt;
        address predicted;
        for (uint256 i = 0; i < 500_000; i++) {
            salt = bytes32(i);
            predicted = vm.computeCreate2Address(salt, keccak256(bytecode), address(this));
            if ((uint160(predicted) & flagMask) == requiredFlags) break;
        }
        deployed = new RudderHook{salt: salt}(_manager, _owner);
        require(address(deployed) == predicted, "hook mine failed");
    }

    function _fund(address who, uint256 amount0, uint256 amount1) internal {
        token0.mint(who, amount0);
        token1.mint(who, amount1);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(vault), type(uint256).max);
        IERC20(address(token1)).approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _approve(address who, address spender) internal {
        vm.startPrank(who);
        IERC20(address(token0)).approve(spender, type(uint256).max);
        IERC20(address(token1)).approve(spender, type(uint256).max);
        vm.stopPrank();
    }

    function _deposit(address who, uint256 amount0, uint256 amount1) internal returns (uint256 shares) {
        vm.prank(who);
        shares = vault.deposit(amount0, amount1, who);
    }

    function _swap(bool zeroForOne, int256 amountSpecified) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        router.swap(key, zeroForOne, amountSpecified, limit);
    }

    function _sqrtPrice() internal view returns (uint160 sp) {
        (sp,,,) = IPoolManager(address(manager)).getSlot0(key.toId());
    }
}
