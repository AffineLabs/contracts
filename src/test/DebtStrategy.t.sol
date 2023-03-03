// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {Deploy} from "./Deploy.sol";

import {DebtStrategy} from "src/strategies/DebtStrategy.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

/// @notice Test general functionalities of strategies.
contract DebtStrategyTest is TestPlus {
    DebtStrategy strategy;
    BaseVault vault;
    ERC20 asset;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        address[] memory strategists = new address[](2);
        strategists[0] = alice;
        strategists[1] = bob;
        strategy = new DebtStrategy(AffineVault(address(vault)), strategists);
        asset = ERC20(vault.asset());
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
        assertEq(asset.balanceOf(address(strategy)), 0);

        // asset in vault
        assertEq(asset.balanceOf(address(vault)), debtAmount);
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
        assertEq(asset.balanceOf(address(strategy)), strategyAssets - debtAmount);

        // asset in vault
        assertEq(asset.balanceOf(address(vault)), debtAmount);
    }

    /**
     * @notice test divest with less assets than debt in strategy
     * @dev we resolve debt with full amount, so less amount could not be resolved automatically
     * @dev need the strategist to run partial resolving.
     */
    function testDivestWithLessAssets() public {
        uint256 debtAmount = 100;
        uint256 strategyAssets = 50;
        // passing asset to the strategy
        deal(vault.asset(), address(strategy), strategyAssets);

        vm.prank(address(vault));

        // divest
        strategy.divest(debtAmount);

        // remaining debt
        assertEq(strategy.debt(), debtAmount);

        // remaining asset in strategy
        assertEq(asset.balanceOf(address(strategy)), strategyAssets);

        // asset in vault
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    /**
     * @notice Resolving partial debt can only be done by strategists
     */
    function testResolvePartialDebt() public {
        uint256 debtAmount = 100;
        uint256 strategyAssets = 50;
        // passing asset to the strategy
        deal(vault.asset(), address(strategy), strategyAssets);

        vm.prank(address(vault));

        // divest
        strategy.divest(debtAmount);

        // remaining debt
        assertEq(strategy.debt(), debtAmount);

        // remaining asset in strategy
        assertEq(asset.balanceOf(address(strategy)), strategyAssets);

        // asset in vault
        assertEq(asset.balanceOf(address(vault)), 0);

        vm.prank(alice);
        strategy.settleDebt();

        // remaining debt
        assertEq(strategy.debt(), debtAmount - strategyAssets);
        // remaining asset in strategy
        assertEq(asset.balanceOf(address(strategy)), 0);

        // asset in vault
        assertEq(asset.balanceOf(address(vault)), strategyAssets);
    }

    function testSettleWithNotStrategist() public {
        uint256 debtAmount = 100;
        uint256 strategyAssets = 50;
        // passing asset to the strategy
        deal(vault.asset(), address(strategy), strategyAssets);

        vm.prank(address(vault));

        // divest
        strategy.divest(debtAmount);

        // remaining debt
        assertEq(strategy.debt(), debtAmount);

        // call should revert not having strategist role
        vm.expectRevert();
        strategy.settleDebt();
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
