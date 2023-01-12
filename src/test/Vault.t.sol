// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {Vault} from "../both/Vault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Test common vault functionalities.
contract EthVaultTest is TestPlus {
    using stdStorage for StdStorage;

    Vault vault;
    MockERC20 asset;

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 6);

        vault = new Vault();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");
    }

    /// @notice Test vault initialization.
    function testInit() public {
        vm.expectRevert();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");

        assertEq(vault.name(), "USD Earn");
        assertEq(vault.symbol(), "usdEarn");
    }
}
