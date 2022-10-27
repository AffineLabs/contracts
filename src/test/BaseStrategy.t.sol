// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {TestStrategy} from "./mocks/TestStrategy.sol";

import {BaseVault} from "../BaseVault.sol";

contract BaseStrategyTest is TestPlus {
    TestStrategy strategy;
    MockERC20 rewardToken;

    function setUp() public {
        rewardToken = new MockERC20("Mock Token", "MT", 18);
        BaseVault vault = Deploy.deployL2Vault();
        strategy = new TestStrategy( vault);
    }

    function testSweep() public {
        // Will revert if non governance tries to call it
        vm.expectRevert("BS: only governance");
        changePrank(alice); // vitalik
        strategy.sweep(rewardToken);

        // Will revert if trying to sell `token` of BaseStrategy
        ERC20 assetToken = ERC20(strategy.vault().asset());
        vm.expectRevert("BS: !asset");
        changePrank(governance);
        strategy.sweep(assetToken);

        // award the strategy some tokens
        rewardToken.mint(address(strategy), 1e18);
        strategy.sweep(rewardToken);

        // Governance addr received reward tokens
        assertEq(rewardToken.balanceOf(governance), 1e18);
        assertEq(rewardToken.balanceOf(address(strategy)), 0);
    }
}
