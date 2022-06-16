// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

import { BaseStrategy } from "../BaseStrategy.sol";
import { BaseVault } from "../BaseVault.sol";

contract MockStrategy is BaseStrategy {
    constructor(BaseVault _vault) {
        vault = _vault;
        token = ERC20(vault.asset());
    }

    function invest(uint256 amount) external override {}

    function divest(uint256 amount) public pure override returns (uint256) {
        amount;
        return 0;
    }

    function balanceOfToken() external view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function totalLockedValue() public pure override returns (uint256) {
        return 0;
    }
}

contract BaseStrategyTest is TestPlus {
    MockStrategy strategy;
    MockERC20 rewardToken;

    function setUp() public {
        rewardToken = new MockERC20("Mock Token", "MT", 18);
        BaseVault vault = Deploy.deployL2Vault();
        strategy = new MockStrategy(vault);
    }

    function testSweep() public {
        // Will revert if non governance tries to call it
        vm.expectRevert(bytes("ONLY_GOVERNANCE"));
        vm.prank(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045); // vitalik
        strategy.sweep(rewardToken);

        // Will revert if trying to sell `token` of BaseStrategy
        ERC20 assetToken = ERC20(strategy.vault().asset());
        vm.expectRevert(bytes("!token"));
        strategy.sweep(assetToken);

        // award the strategy some tokens
        rewardToken.mint(address(strategy), 1e18);
        strategy.sweep(rewardToken);

        // This contract is the governance address, and so should receive the awarded tokens
        assertEq(rewardToken.balanceOf(address(this)), 1e18);
        assertEq(rewardToken.balanceOf(address(strategy)), 0);
    }
}
