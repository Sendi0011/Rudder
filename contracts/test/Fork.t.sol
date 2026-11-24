// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";

/// @notice End-to-end lifecycle against the REAL Unichain Sepolia v4 PoolManager.
///         Requires `UNICHAIN_SEPOLIA_RPC_URL`; the test is skipped when it is unset so the default
///         (offline) suite and CI stay green.
///
/// Run:
///   UNICHAIN_SEPOLIA_RPC_URL=<rpc> forge test --match-contract ForkLifecycleTest -vvv
contract ForkLifecycleTest is Test {
    using StateLibrary for IPoolManager;

    address internal constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address internal constant POOL_SWAP_TEST = 0x9140a78c1A137c7fF1c151EC8231272aF78a99A4;

    int24 internal constant START_TICK = 0;
    int24 internal constant FIRST_LOWER = -600;
    int24 internal constant FIRST_UPPER = 600;
    int24 internal constant NEXT_LOWER = -1200;
    int24 internal constant NEXT_UPPER = 1200;
    uint256 internal constant MAX_TICK_DRIFT = 60;
    uint256 internal constant SWAP_AMOUNT = 1e15;
    uint256 internal constant TRADER_FUND = SWAP_AMOUNT * 4;

    IPoolManager internal manager;
    TestERC20 internal token0;
    TestERC20 internal token1;
    PoolSwapTest internal swapper;
    PoolKey internal key;

    StrategyRegistry internal registry;
    VaultFactory internal factory;
    RudderHook internal hook;
    RudderVault internal vault;
    uint256 internal strategyId;

    address internal curator = address(0xC0);
    address internal lp = address(0x11);
    address internal trader = address(0x22);

    function setUp() public {
        string memory rpc = vm.envOr("UNICHAIN_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpc);

        manager = IPoolManager(POOL_MANAGER);
        swapper = PoolSwapTest(POOL_SWAP_TEST);

        (token0, token1) = _deploySortedTokens();
        token0.mint(trader, TRADER_FUND);
        token1.mint(trader, TRADER_FUND);

        registry = new StrategyRegistry();
        RudderVault implementation = new RudderVault();

        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (address expectedHook, bytes32 salt) = _mineHook(flags, abi.encode(manager, address(this)));
        hook = new RudderHook{salt: salt}(manager, address(this));
        assertEq(address(hook), expectedHook, "mined hook address mismatched at deploy");

        factory = new VaultFactory(address(implementation), manager, address(registry), address(hook));
        hook.setVaultFactory(address(factory));
        registry.setFactory(address(factory));

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, TickMath.getSqrtPriceAtTick(START_TICK));

        Envelope memory env = Envelope({
            maxRangeWidth: 6000,
            maxCenterShift: 3000,
            maxTwapDistanceTicks: 6000,
            minRebalanceInterval: 1,
            maxPriceImpactBps: 10_000,
            maxNavLossBps: -500,
            maxDailyNavLossBps: 1000
        });
        vm.prank(curator);
        strategyId = registry.registerStrategy(env);

        vm.deal(curator, 1 ether);
        vm.prank(curator);
        vault = RudderVault(factory.createVault(strategyId, key, 1000));
        assertTrue(factory.isVault(address(vault)), "factory must recognize the vault");
        assertEq(registry.strategyVault(strategyId), address(vault), "strategy must be bound to vault");

        vm.prank(curator);
        vault.rebalance(FIRST_LOWER, FIRST_UPPER);
    }

    function test_Fork_DepositSwapRebalanceWithdraw() public {
        _fund(lp, 1_000e18, 1_000e18);

        // SeedFlow order: the first range is set before the deposit, so swaps have liquidity.
        vm.prank(lp);
        uint256 shares = vault.deposit(1_000e18, 1_000e18, lp);
        assertGt(shares, 0, "deposit must mint shares");
        assertGt(vault.positionLiquidity(), 0, "vault must hold liquidity before swaps");

        // Two small swaps with a warp between them => >= 2 fresh observations (oracle ready).
        _externalSwap(true, SWAP_AMOUNT);
        vm.warp(block.timestamp + 10);
        _externalSwap(false, SWAP_AMOUNT);
        vm.warp(block.timestamp + 10);

        (, int24 tick,,) = manager.getSlot0(key.toId());
        assertApproxEqAbs(int256(tick), int256(START_TICK), MAX_TICK_DRIFT, "tick left the start band");
        assertTrue(hook.isOracleReady(key), "oracle must be ready after two swaps");

        // Warp past the rebalance interval, then widen the range inside the envelope.
        vm.warp(block.timestamp + 10);
        vm.prank(curator);
        vault.rebalance(NEXT_LOWER, NEXT_UPPER);

        // Deposit now that the oracle is ready, then withdraw everything.
        _fund(lp, 100e18, 100e18);
        vm.prank(lp);
        vault.deposit(100e18, 100e18, lp);

        uint256 bal = vault.balanceOf(lp);
        uint256 before0 = token0.balanceOf(lp);
        uint256 before1 = token1.balanceOf(lp);
        vm.prank(lp);
        vault.withdraw(bal, lp);

        assertEq(vault.balanceOf(lp), 0, "all shares redeemed");
        assertGt(token0.balanceOf(lp) - before0, 0, "lp receives token0 on exit");
        assertGt(token1.balanceOf(lp) - before1, 0, "lp receives token1 on exit");
    }

    // --- helpers ---------------------------------------------------------------------------------

    function _deploySortedTokens() internal returns (TestERC20 a, TestERC20 b) {
        TestERC20 x = new TestERC20(1e30);
        TestERC20 y = new TestERC20(1e30);
        (a, b) = address(x) < address(y) ? (x, y) : (y, x);
    }

    function _fund(address who, uint256 amount0, uint256 amount1) internal {
        token0.mint(who, amount0);
        token1.mint(who, amount1);
        vm.startPrank(who);
        IERC20(address(token0)).approve(address(vault), type(uint256).max);
        IERC20(address(token1)).approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _externalSwap(bool zeroForOne, uint256 amount) internal {
        uint160 limit = zeroForOne ? TickMath.getSqrtPriceAtTick(FIRST_LOWER) : TickMath.getSqrtPriceAtTick(FIRST_UPPER);
        vm.startPrank(trader);
        IERC20(address(token0)).approve(address(swapper), type(uint256).max);
        IERC20(address(token1)).approve(address(swapper), type(uint256).max);
        swapper.swap(
            key,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amount), sqrtPriceLimitX96: limit}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.stopPrank();
    }

    function _mineHook(uint160 flags, bytes memory constructorArgs) internal view returns (address, bytes32) {
        bytes memory code = abi.encodePacked(type(RudderHook).creationCode, constructorArgs);
        bytes32 codeHash = keccak256(code);
        flags = flags & Hooks.ALL_HOOK_MASK;
        for (uint256 salt; salt < 300_000; ++salt) {
            address candidate = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), codeHash))))
            );
            if (uint160(candidate) & Hooks.ALL_HOOK_MASK == flags) {
                return (candidate, bytes32(salt));
            }
        }
        revert("HookMiner: could not find salt");
    }
}
