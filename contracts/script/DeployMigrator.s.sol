// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {VaultMigrator} from "../src/VaultMigrator.sol";

contract DeployMigrator is Script {
    function run() external returns (VaultMigrator migrator) {
        vm.startBroadcast();
        migrator = new VaultMigrator();
        vm.stopBroadcast();

        _writeDeployment(address(migrator));
        console2.log("vaultMigrator", address(migrator));
    }

    function _writeDeployment(address migrator) internal {
        if (vm.envOr("WRITE_DEPLOYMENTS", uint256(0)) == 0) return;
        string memory raw = vm.readFile("./contracts/deployments.json");
        string memory obj = "rudder";
        vm.serializeUint(obj, "chainId", vm.parseJsonUint(raw, ".chainId"));
        vm.serializeAddress(obj, "poolManager", vm.parseJsonAddress(raw, ".poolManager"));
        vm.serializeAddress(obj, "rudderHook", vm.parseJsonAddress(raw, ".rudderHook"));
        vm.serializeAddress(obj, "strategyRegistry", vm.parseJsonAddress(raw, ".strategyRegistry"));
        vm.serializeAddress(obj, "vaultFactory", vm.parseJsonAddress(raw, ".vaultFactory"));
        vm.serializeAddress(obj, "vaultImplementation", vm.parseJsonAddress(raw, ".vaultImplementation"));
        string memory json = vm.serializeAddress(obj, "vaultMigrator", migrator);
        vm.writeJson(json, "./contracts/deployments.json");
    }
}
