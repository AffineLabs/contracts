// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {TestStrategy} from "./mocks/TestStrategy.sol";

import {BaseVault} from "src/BaseVault.sol";

/// @notice Test general functionalities of strategies.
contract BaseStrategyTest is TestPlus {
    TestStrategy strategy;
    MockERC20 rewardToken;

    function setUp() public {
        rewardToken = new MockERC20("Mock Token", "MT", 18);
        BaseVault vault = Deploy.deployL2Vault();
        strategy = new TestStrategy(vault);
    }

    /// @notice Test only governance can sweep tokens from vaults.
    function testSweep() public {
        // Will revert if non governance tries to call it
        vm.expectRevert("BS: only governance");
        changePrank(alice); // vitalik
        strategy.sweep(rewardToken);

        changePrank(governance);
        // award the strategy some tokens
        rewardToken.mint(address(strategy), 1e18);
        strategy.sweep(rewardToken);

        // Governance addr received reward tokens
        assertEq(rewardToken.balanceOf(governance), 1e18);
        assertEq(rewardToken.balanceOf(address(strategy)), 0);
    }
}
