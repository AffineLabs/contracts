// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import "forge-std/Components.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "src/test/TestPlus.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {TestStrategy} from "./mocks/TestStrategy.sol";

contract WithdrawalEscrowTest is TestPlus {
    StrategyVault vault;
    MockERC20 asset;
    WithdrawalEscrow withdrawalEscrow;
    TestStrategy strategy;

    // initial user assets
    uint256 initialAssets;
    uint256 initialTVL;
    uint256 aliceShares;
    uint256 bobShares;

    uint256 initialWithdrawAmount;

    function setUp() public {
        initialAssets = 100e6;
        asset = new MockERC20("Mock", "MT", 6);
        vault = new StrategyVault();
        vault.initialize(governance, address(asset), "Test Vault", "TV");
        strategy = new TestStrategy(AffineVault(address(vault)));
        vm.startPrank(governance);
        vault.setStrategy(strategy);
        vault.setTvlCap(type(uint256).max);
        vault.grantRole(vault.HARVESTER(), address(this));
        vm.stopPrank();
        withdrawalEscrow = new WithdrawalEscrow(vault);

        // assign assets to alice & bob
        asset.mint(alice, initialAssets);
        asset.mint(bob, initialAssets);

        // buy vault shares for alice & bob
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        changePrank(bob);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, bob);

        initialTVL = asset.balanceOf(address(vault));
        aliceShares = vault.balanceOf(alice);
        bobShares = vault.balanceOf(bob);

        initialWithdrawAmount = aliceShares / 10;

        vm.stopPrank();
    }

    /**
     * @notice Test debt registering
     *  @dev vault needs to lock the shares first before registering debt.
     *  @dev otherwise registering will be failed.
     */
    function testRegisterDebt() public {
        vm.startPrank(address(vault));
        // register debt for alice
        // send assets to vault before register
        deal(address(vault), address(withdrawalEscrow), initialWithdrawAmount);
        deal(address(vault), alice, aliceShares - initialWithdrawAmount);

        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);

        uint256 epoch = vault.epoch();
        (uint256 recordedShares,) = withdrawalEscrow.epochInfo(epoch);
        //check map for current epoch
        assertEq(withdrawalEscrow.userDebtShare(epoch, alice), initialWithdrawAmount);
        assertEq(recordedShares, initialWithdrawAmount);
    }

    /// @notice test resolving debt for a single epoch
    function testResolveDebt() public {
        // manually transfer vault shares from alice to escrow
        deal(address(vault), alice, aliceShares - initialWithdrawAmount);
        deal(address(vault), address(withdrawalEscrow), initialWithdrawAmount);

        // register debt for alice
        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);
        withdrawalEscrow.resolveDebtShares();

        assertEq(vault.balanceOf(address(withdrawalEscrow)), 0);
        assertEq(asset.balanceOf(address(withdrawalEscrow)), initialAssets / 10);
        // total supply should drop by withdrawal amount
        assertEq(vault.totalSupply(), aliceShares + bobShares - initialWithdrawAmount);
    }

    /// @notice test redeem assets for a single user
    function testRedeem() public {
        vm.startPrank(address(vault));

        // manually transfer assets from alice to escrow
        deal(address(vault), alice, aliceShares - initialWithdrawAmount);
        deal(address(vault), address(withdrawalEscrow), initialWithdrawAmount);

        // register debt for alice
        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);

        withdrawalEscrow.resolveDebtShares();

        // console.log("withdrable shares", withdrawalEscrow.withdrawableShares(alice, 0));
        // console.log("withdrable assets", withdrawalEscrow.withdrawableAssets(alice, 0));

        assertEq(withdrawalEscrow.withdrawableShares(alice, 0), initialWithdrawAmount);

        assertEq(withdrawalEscrow.withdrawableAssets(alice, 0), initialAssets / 10);

        uint256 escrowAssets = asset.balanceOf(address(withdrawalEscrow));
        // redeem assets

        withdrawalEscrow.redeem(alice, 0);

        // alice should get the full amount of asset
        assertEq(asset.balanceOf(address(withdrawalEscrow)), 0);
        assertEq(asset.balanceOf(alice), escrowAssets);
    }

    /// @notice test multiple user withdrawal from escrow.
    function testMultipleWithdrawal() public {
        vm.startPrank(address(vault));

        // send the shares to escrow before registering debt
        deal(address(vault), address(withdrawalEscrow), initialWithdrawAmount);
        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);

        // bob withdraw double of alice
        // send the shares of bob to escrow before registering debt
        deal(address(vault), address(withdrawalEscrow), 3 * initialWithdrawAmount);
        withdrawalEscrow.registerWithdrawalRequest(bob, 2 * initialWithdrawAmount);

        // manually set the amount for vault and withdrawal escrow
        deal(address(vault), alice, aliceShares - initialWithdrawAmount);
        deal(address(vault), bob, bobShares - 2 * initialWithdrawAmount);

        // resolve debt shares for the escrow

        withdrawalEscrow.resolveDebtShares();

        uint256 escrowAssets = asset.balanceOf(address(withdrawalEscrow));

        // check for assets and shares
        // for alice
        assertEq(withdrawalEscrow.withdrawableShares(alice, 0), initialWithdrawAmount);
        assertEq(withdrawalEscrow.withdrawableAssets(alice, 0), escrowAssets / 3);

        // for bob
        assertEq(withdrawalEscrow.withdrawableShares(bob, 0), 2 * initialWithdrawAmount);
        assertEq(withdrawalEscrow.withdrawableAssets(bob, 0), (2 * escrowAssets) / 3);

        withdrawalEscrow.redeem(alice, 0);
        withdrawalEscrow.redeem(bob, 0);

        // all the shares of escrow should be resolved
        assertEq(vault.balanceOf(address(withdrawalEscrow)), 0);
        assertEq(vault.totalSupply(), aliceShares + bobShares - 3 * initialWithdrawAmount);

        // assets received by alice and bob

        assertEq(asset.balanceOf(alice), escrowAssets / 3);
        assertEq(asset.balanceOf(bob), (2 * escrowAssets) / 3);

        // assets of the escrow should be zero
        assertEq(asset.balanceOf(address(withdrawalEscrow)), 0);
    }

    ///@notice Ending the epoch should still work even if know withdrawal requests are made
    function testEmptyEpoch() public {
        vm.prank(address(strategy));
        vault.beginEpoch();

        vm.prank(address(strategy));
        vault.endEpoch();
    }
}
