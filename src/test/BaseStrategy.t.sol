// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

import { TestStrategy } from "./mocks/TestStrategy.sol";

import { BaseVault } from "../BaseVault.sol";

contract BaseStrategyTest is TestPlus {
    TestStrategy strategy;
    MockERC20 rewardToken;

    function setUp() public {
        rewardToken = new MockERC20("Mock Token", "MT", 18);
        BaseVault vault = Deploy.deployL2Vault();
        strategy = new TestStrategy(MockERC20(vault.asset()), vault);
    }

    function testSweep() public {
        // Will revert if non governance tries to call it
        vm.expectRevert(bytes("ONLY_GOVERNANCE"));
        vm.prank(mkaddr("vitalik")); // vitalik
        strategy.sweep(rewardToken);

        // Will revert if trying to sell `token` of BaseStrategy
        ERC20 assetToken = ERC20(strategy.vault().asset());
        vm.expectRevert(bytes("!asset"));
        strategy.sweep(assetToken);

        // award the strategy some tokens
        rewardToken.mint(address(strategy), 1e18);
        strategy.sweep(rewardToken);

        // This contract is the governance address, and so should receive the awarded tokens
        assertEq(rewardToken.balanceOf(address(this)), 1e18);
        assertEq(rewardToken.balanceOf(address(strategy)), 0);
    }
}
