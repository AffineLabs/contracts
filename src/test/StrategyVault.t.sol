// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {Vault} from "src/vaults/Vault.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";

contract SVaultTest is TestPlus {
    using stdStorage for StdStorage;

    StrategyVault vault;
    MockERC20 asset;

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 6);

        vault = new StrategyVault();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");
    }

    function testTvlCap() public {
        vm.prank(governance);
        vault.setTvlCap(1000);

        asset.mint(address(this), 2000);
        asset.approve(address(vault), type(uint256).max);

        vault.deposit(500, address(this));
        assertEq(asset.balanceOf(address(this)), 1500);

        // We only deposit 500 because the limit is 500 and 500 is already in the vault
        vault.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);

        vm.expectRevert("Vault: deposit limit reached");
        vault.deposit(200, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);
    }
}
