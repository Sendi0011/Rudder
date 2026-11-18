// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {RudderHook} from "../src/RudderHook.sol";
import {Seed} from "../script/Seed.s.sol";

contract SeedFlowHarness is Seed {
    function seed(address managerAddr, address registryAddr, address factoryAddr, address hookAddr, address curator)
        external
        returns (SeedState memory)
    {
        return _seed(managerAddr, registryAddr, factoryAddr, hookAddr, curator);
    }
}

contract SeedFlowTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 internal constant TRADE = 1e12;
    int24 internal constant START_TICK = 0;

    function test_SeedOrderKeepsPoolUsable() public {
        vm.setEnv("START_TICK", vm.toString(int256(START_TICK)));
        vm.setEnv("TICK_SPACING", "60");
        vm.setEnv("POOL_FEE", "3000");
        vm.setEnv("DEPOSIT0", "100000000000000000000");
        vm.setEnv("DEPOSIT1", "100000000000000000000");
        vm.setEnv("TOKEN0", "0x0000000000000000000000000000000000000000");
        vm.setEnv("TOKEN1", "0x0000000000000000000000000000000000000000");

        PoolManager manager = new PoolManager(address(this));
        StrategyRegistry registry = new StrategyRegistry();
        RudderVault impl = new RudderVault();
        RudderHook hook = _deployMinedHook(IPoolManager(address(manager)));
        VaultFactory factory =
            new VaultFactory(address(impl), IPoolManager(address(manager)), address(registry), address(hook));
        hook.setVaultFactory(address(factory));
        registry.setFactory(address(factory));

        SeedFlowHarness seeder = new SeedFlowHarness();
        Seed.SeedState memory s =
            seeder.seed(address(manager), address(registry), address(factory), address(hook), address(this));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(s.token0),
            currency1: Currency.wrap(s.token1),
            fee: s.fee,
            tickSpacing: s.tickSpacing,
            hooks: IHooks(address(hook))
        });

        PoolSwapTest router = PoolSwapTest(s.router);
        IERC20(s.token0).approve(s.router, type(uint256).max);
        IERC20(s.token1).approve(s.router, type(uint256).max);
        router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -int256(TRADE), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        router.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -int256(TRADE), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        (, int24 tick,,) = IPoolManager(address(manager)).getSlot0(key.toId());
        assertApproxEqAbs(int256(tick), int256(START_TICK), 60, "tick moved away from start");
        for (uint256 i; i < s.vaults.length; ++i) {
            assertGt(RudderVault(s.vaults[i]).positionLiquidity(), 0, "vault has no liquidity");
        }
        assertGe(hook.observationCount(key), 2, "oracle has too few samples");
        assertTrue(hook.isOracleReady(key), "oracle is not ready");
    }

    function _deployMinedHook(IPoolManager manager) internal returns (RudderHook deployed) {
        bytes memory args = abi.encode(manager, address(this));
        bytes memory bytecode = abi.encodePacked(type(RudderHook).creationCode, args);
        uint160 requiredFlags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        bytes32 salt;
        address predicted;
        for (uint256 i; i < 500_000; ++i) {
            salt = bytes32(i);
            predicted = vm.computeCreate2Address(salt, keccak256(bytecode), address(this));
            if ((uint160(predicted) & 0x3FFF) == requiredFlags) break;
        }
        deployed = new RudderHook{salt: salt}(manager, address(this));
        require(address(deployed) == predicted, "hook mine failed");
    }
}
