// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {RudderVault} from "../src/RudderVault.sol";
import {Envelope} from "../src/libraries/EnvelopeLib.sol";

contract Seed is Script {
    error InvalidStartTick();

    struct SeedState {
        address token0;
        address token1;
        address router;
        address[3] vaults;
        uint24 fee;
        int24 tickSpacing;
        int24 startingTick;
    }

    function run() external returns (SeedState memory s) {
        string memory deployment = vm.readFile("./contracts/deployments.json");
        address managerAddr = vm.parseJsonAddress(deployment, ".poolManager");
        address registryAddr = vm.parseJsonAddress(deployment, ".strategyRegistry");
        address factoryAddr = vm.parseJsonAddress(deployment, ".vaultFactory");
        address hookAddr = vm.parseJsonAddress(deployment, ".rudderHook");

        vm.startBroadcast();
        s = _seed(managerAddr, registryAddr, factoryAddr, hookAddr, msg.sender);
        vm.stopBroadcast();

        _writeSeed(managerAddr, hookAddr, s);
    }

    function _seed(address managerAddr, address registryAddr, address factoryAddr, address hookAddr, address curator)
        internal
        returns (SeedState memory s)
    {
        uint256 deposit0 = vm.envOr("DEPOSIT0", uint256(100e18));
        uint256 deposit1 = vm.envOr("DEPOSIT1", uint256(100e18));
        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 spacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        int24 startingTick = int24(vm.envOr("START_TICK", int256(0)));

        if (
            startingTick % spacing != 0 || startingTick < TickMath.minUsableTick(spacing)
                || startingTick > TickMath.maxUsableTick(spacing)
        ) revert InvalidStartTick();

        address token0Addr = vm.envOr("TOKEN0", address(0));
        address token1Addr = vm.envOr("TOKEN1", address(0));
        if (token0Addr == address(0) || token1Addr == address(0)) {
            TestERC20 token0Deployed = new TestERC20(1e30);
            TestERC20 token1Deployed = new TestERC20(1e30);
            token0Addr = address(token0Deployed);
            token1Addr = address(token1Deployed);
            token0Deployed.mint(curator, 1e28);
            token1Deployed.mint(curator, 1e28);
        }
        (token0Addr, token1Addr) = token0Addr < token1Addr ? (token0Addr, token1Addr) : (token1Addr, token0Addr);

        PoolSwapTest router = new PoolSwapTest(IPoolManager(managerAddr));
        IERC20(token0Addr).approve(address(router), type(uint256).max);
        IERC20(token1Addr).approve(address(router), type(uint256).max);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0Addr),
            currency1: Currency.wrap(token1Addr),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(hookAddr)
        });
        IPoolManager(managerAddr).initialize(key, TickMath.getSqrtPriceAtTick(startingTick));

        Envelope[3] memory envelopes;
        envelopes[0] = Envelope({
            maxRangeWidth: 1200,
            maxCenterShift: 600,
            maxTwapDistanceTicks: 1200,
            minRebalanceInterval: 3600,
            maxPriceImpactBps: 200,
            maxNavLossBps: -50,
            maxDailyNavLossBps: 200
        });
        envelopes[1] = Envelope({
            maxRangeWidth: 2400,
            maxCenterShift: 1200,
            maxTwapDistanceTicks: 2400,
            minRebalanceInterval: 1800,
            maxPriceImpactBps: 500,
            maxNavLossBps: -100,
            maxDailyNavLossBps: 500
        });
        envelopes[2] = Envelope({
            maxRangeWidth: 4800,
            maxCenterShift: 2400,
            maxTwapDistanceTicks: 4800,
            minRebalanceInterval: 600,
            maxPriceImpactBps: 1000,
            maxNavLossBps: -200,
            maxDailyNavLossBps: 1000
        });

        int24[3] memory lowers = [int24(-600), int24(-1200), int24(-2400)];
        int24[3] memory uppers = [int24(600), int24(1200), int24(2400)];
        for (uint256 i; i < 3; ++i) {
            uint256 id = StrategyRegistry(registryAddr).registerStrategy(envelopes[i]);
            address vaultAddr = VaultFactory(factoryAddr).createVault(id, key, 1000);
            IERC20(token0Addr).approve(vaultAddr, type(uint256).max);
            IERC20(token1Addr).approve(vaultAddr, type(uint256).max);
            RudderVault(vaultAddr).rebalance(lowers[i], uppers[i]);
            RudderVault(vaultAddr).deposit(deposit0, deposit1, curator);
            s.vaults[i] = vaultAddr;
        }

        s.token0 = token0Addr;
        s.token1 = token1Addr;
        s.router = address(router);
        s.fee = fee;
        s.tickSpacing = spacing;
        s.startingTick = startingTick;
    }

    function _writeSeed(address managerAddr, address hookAddr, SeedState memory s) internal {
        string memory obj = "seed";
        vm.serializeAddress(obj, "poolManager", managerAddr);
        vm.serializeAddress(obj, "rudderHook", hookAddr);
        vm.serializeAddress(obj, "token0", s.token0);
        vm.serializeAddress(obj, "token1", s.token1);
        vm.serializeAddress(obj, "router", s.router);
        vm.serializeAddress(obj, "vault0", s.vaults[0]);
        vm.serializeAddress(obj, "vault1", s.vaults[1]);
        vm.serializeAddress(obj, "vault2", s.vaults[2]);
        vm.serializeUint(obj, "fee", s.fee);
        vm.serializeUint(obj, "tickSpacing", uint256(int256(s.tickSpacing)));
        string memory json = vm.serializeInt(obj, "startingTick", int256(s.startingTick));
        vm.writeJson(json, "./contracts/seed.json");
    }
}
