// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {DebtStrategy} from "src/strategies/DebtStrategy.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

/// @notice Test general functionalities of strategies.
contract DebtStrategyTest is TestPlus {
    DebtStrategy strategy;
    MockERC20 rewardToken;
    BaseVault vault;

    function setUp() public {
        rewardToken = new MockERC20("Mock Token", "MT", 18);
        vault = Deploy.deployL2Vault();
        address[] memory strategiest = new address[](2);
        strategiest[0] = alice;
        strategiest[1] = bob;
        strategy = new DebtStrategy(AffineVault(address(vault)), strategiest);
    }

    /**
     * @notice test revert in strategy without vault
     * @dev will try to divest from different address
     */
    function testDivestFromUser() public {
        vm.expectRevert("BS: only vault");
        strategy.divest(100);
    }

    /**
     * @notice test divest from vault address
     * @dev will try to divest from strategy and check debt in strategy
     */
    function testDivestFromVault() public {
        uint256 debtAmount = 100;

        vm.prank(address(vault));

        // divest 100
        strategy.divest(debtAmount);

        // check debt amount
        assertEq(strategy.debt(), debtAmount);
    }

    /**
     * @notice test divest with equal debt assets in strategy
     */
    function testDivestWithEqAssets() public {
        uint256 debtAmount = 100;
        // assing asset to the strategy
        deal(vault.asset(), address(strategy), debtAmount);
        vm.prank(address(vault));

        // divest
        strategy.divest(debtAmount);

        // remaining debt
        assertEq(strategy.debt(), 0);

        // remaining asset in strategy
        assertEq(ERC20(vault.asset()).balanceOf(address(strategy)), 0);

        // asset in vault
        assertEq(ERC20(vault.asset()).balanceOf(address(vault)), debtAmount);
    }

    /**
     * @notice test divest with more assets than debt in strategy
     */
    function testDivestWithMoreAssets() public {
        uint256 debtAmount = 100;
        uint256 strategyAssets = 200;
        // assing asset to the strategy
        deal(vault.asset(), address(strategy), strategyAssets);

        vm.prank(address(vault));

        // divest
        strategy.divest(debtAmount);

        // remaining debt
        assertEq(strategy.debt(), 0);

        // remaining asset in strategy
        assertEq(ERC20(vault.asset()).balanceOf(address(strategy)), strategyAssets - debtAmount);

        // asset in vault
        assertEq(ERC20(vault.asset()).balanceOf(address(vault)), debtAmount);
    }

    /**
     * @notice test divest with less assets than debt in strategy
     */
    function testDivestWithLessAssets() public {
        uint256 debtAmount = 100;
        uint256 strategyAssets = 50;
        // assing asset to the strategy
        deal(vault.asset(), address(strategy), strategyAssets);

        vm.prank(address(vault));

        // divest
        strategy.divest(debtAmount);

        // remaining debt
        assertEq(strategy.debt(), debtAmount - strategyAssets);

        // remaining asset in strategy
        assertEq(ERC20(vault.asset()).balanceOf(address(strategy)), 0);

        // asset in vault
        assertEq(ERC20(vault.asset()).balanceOf(address(vault)), strategyAssets);
    }

    /**
     * @notice test debt reset
     */
    function testDebtReset() public {
        uint256 debtAmount = 100;
        // prank vault
        vm.startPrank(address(vault));

        // divest 100
        strategy.divest(debtAmount);

        // check debt
        assertEq(strategy.debt(), debtAmount);

        // reset debt
        strategy.resetDebt();

        // check debt
        assertEq(strategy.debt(), 0);
    }
}
