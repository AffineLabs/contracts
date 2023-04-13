// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import "forge-std/Components.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "src/test/TestPlus.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {Vault} from "src/vaults/Vault.sol";
import {SingleStrategyWithdrawalEscrow} from "src/vaults/SingleStrategyWithdrawal.sol";

contract SingleStrategyWithdrawalTest is TestPlus {
    Vault vault;
    MockERC20 asset;
    SingleStrategyWithdrawalEscrow withdrawalEscrow;

    // initial user assets
    uint256 initialAssets;
    uint256 initialTVL;
    uint256 aliceShares;
    uint256 bobShares;

    uint256 initialWithdrawAmount;

    function setUp() public {
        initialAssets = 1_000_000_000_000;
        asset = new MockERC20("Mock", "MT", 6);
        vault = new Vault();
        vault.initialize(governance, address(asset), "Test Vault", "TV");
        withdrawalEscrow = new SingleStrategyWithdrawalEscrow(vault);

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

        console.log("vault tvl", initialTVL);
        console.log("alice shares", aliceShares);
        console.log("bob shares", aliceShares);

        initialWithdrawAmount = aliceShares / 10;

        vm.stopPrank();
    }

    function testRegisterDebt() public {
        vm.startPrank(address(vault));
        // register debt for alice
        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);

        //check map for current epoch
        assertEq(withdrawalEscrow.userDebtShare(withdrawalEscrow.currentEpoch(), alice), initialWithdrawAmount);
        assertEq(withdrawalEscrow.epochDebt(withdrawalEscrow.currentEpoch()), initialWithdrawAmount);
    }

    function testResolveDebt() public {
        vm.startPrank(address(vault));
        // register debt for alice
        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);

        // manually transfer assets from alice to escrow
        deal(address(vault), alice, aliceShares - initialWithdrawAmount);
        deal(address(vault), address(withdrawalEscrow), initialWithdrawAmount);

        withdrawalEscrow.resolveDebtShares();

        assertEq(vault.balanceOf(address(withdrawalEscrow)), 0);
        assertEq(asset.balanceOf(address(withdrawalEscrow)), initialAssets / 10);
        // change in current epoch
        assertEq(withdrawalEscrow.currentEpoch(), 1);
        // total supply should drop by withdrawal amount
        assertEq(vault.totalSupply(), aliceShares + bobShares - initialWithdrawAmount);
    }

    function testRedeem() public {
        vm.startPrank(address(vault));
        // register debt for alice
        withdrawalEscrow.registerWithdrawalRequest(alice, initialWithdrawAmount);

        // manually transfer assets from alice to escrow
        deal(address(vault), alice, aliceShares - initialWithdrawAmount);
        deal(address(vault), address(withdrawalEscrow), initialWithdrawAmount);

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
}
