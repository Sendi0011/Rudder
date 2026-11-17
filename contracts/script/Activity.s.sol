// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Activity is Script {
    function run() external {
        string memory seed = vm.readFile("./contracts/seed.json");
        address hookAddr = vm.parseJsonAddress(seed, ".rudderHook");
        address token0Addr = vm.parseJsonAddress(seed, ".token0");
        address token1Addr = vm.parseJsonAddress(seed, ".token1");
        address routerAddr = vm.parseJsonAddress(seed, ".router");
        uint24 fee = uint24(vm.parseJsonUint(seed, ".fee"));
        int24 spacing = int24(int256(vm.parseJsonUint(seed, ".tickSpacing")));

        uint256 amount = vm.envOr("SWAP_AMOUNT", uint256(1e15));
        bool zeroForOne = vm.envOr("SWAP_DIRECTION", uint256(0)) == 0;
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0Addr),
            currency1: Currency.wrap(token1Addr),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(hookAddr)
        });

        vm.startBroadcast();
        IERC20(token0Addr).approve(routerAddr, type(uint256).max);
        IERC20(token1Addr).approve(routerAddr, type(uint256).max);
        PoolSwapTest(routerAddr)
            .swap(
                key,
                SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amount), sqrtPriceLimitX96: limit}),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ""
            );
        vm.stopBroadcast();
    }
}
