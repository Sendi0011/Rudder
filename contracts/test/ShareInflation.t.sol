// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RudderTestBase} from "./RudderTestBase.sol";
import {RudderVault} from "../src/RudderVault.sol";

contract ShareInflationTest is RudderTestBase {
    function test_ImplementationExposesMinimumLiquidity() public view {
        assertEq(vaultImpl.MINIMUM_LIQUIDITY(), 1000);
    }

    /// @notice Vaults used by this suite are created through VaultFactory (never constructed directly).
    function test_FactoryVault_EnforcesMinimumLiquidity() public {
        uint256 id = _registerStrategy(curator);
        address vault = _createVault(id, curator);
        assertEq(RudderVault(vault).MINIMUM_LIQUIDITY(), 1000, "factory vault keeps inflation guard");
    }
}
