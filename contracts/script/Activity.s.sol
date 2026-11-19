// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RudderVault} from "../src/RudderVault.sol";

contract Activity is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error RangeExceeded(int24 tick, int24 lower, int24 upper);

    function run() external {
        string memory seed = vm.readFile("./contracts/seed.json");
        address managerAddr = vm.parseJsonAddress(seed, ".poolManager");
        address hookAddr = vm.parseJsonAddress(seed, ".rudderHook");
        address token0Addr = vm.parseJsonAddress(seed, ".token0");
        address token1Addr = vm.parseJsonAddress(seed, ".token1");
        address routerAddr = vm.parseJsonAddress(seed, ".router");
        address[3] memory vaults = [
            vm.parseJsonAddress(seed, ".vault0"),
            vm.parseJsonAddress(seed, ".vault1"),
            vm.parseJsonAddress(seed, ".vault2")
        ];
        uint24 fee = uint24(vm.parseJsonUint(seed, ".fee"));
        int24 spacing = int24(int256(vm.parseJsonUint(seed, ".tickSpacing")));
        int24 startingTick = int24(vm.parseJsonInt(seed, ".startingTick"));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0Addr),
            currency1: Currency.wrap(token1Addr),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(hookAddr)
        });

        (int24 lower, int24 upper) = _narrowestRange(vaults);
        (, int24 tick,,) = IPoolManager(managerAddr).getSlot0(key.toId());

        uint256 direction = vm.envOr("SWAP_DIRECTION", uint256(2));
        bool zeroForOne;
        if (direction == 0 || direction == 1) {
            zeroForOne = direction == 0;
        } else if (tick >= upper) {
            zeroForOne = true;
        } else if (tick <= lower) {
            zeroForOne = false;
        } else if (tick > startingTick) {
            zeroForOne = true;
        } else if (tick < startingTick) {
            zeroForOne = false;
        } else {
            zeroForOne = vm.envOr("ACTIVITY_RUN", uint256(0)) % 2 == 0;
        }

        uint256 amount = vm.envOr("SWAP_AMOUNT", uint256(1e15));
        uint160 limit = zeroForOne ? TickMath.getSqrtPriceAtTick(lower) : TickMath.getSqrtPriceAtTick(upper);

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

        (, int24 postTick,,) = IPoolManager(managerAddr).getSlot0(key.toId());
        if (postTick < lower || postTick > upper) revert RangeExceeded(postTick, lower, upper);
    }

    function _narrowestRange(address[3] memory vaults) internal view returns (int24 lower, int24 upper) {
        lower = RudderVault(vaults[0]).tickLower();
        upper = RudderVault(vaults[0]).tickUpper();
        int24 bestWidth = upper - lower;
        for (uint256 i = 1; i < vaults.length; ++i) {
            int24 lo = RudderVault(vaults[i]).tickLower();
            int24 hi = RudderVault(vaults[i]).tickUpper();
            int24 width = hi - lo;
            if (width < bestWidth) {
                lower = lo;
                upper = hi;
                bestWidth = width;
            }
        }
    }
}
