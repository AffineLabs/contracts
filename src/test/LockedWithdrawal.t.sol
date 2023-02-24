// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "src/test/TestPlus.sol";
import {Deploy} from "./Deploy.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {LockedWithdrawalEscrow} from "src/vaults/LockedWithdrawal.sol";

contract LockedWithdrawalTest is TestPlus {
    BaseVault vault;

    LockedWithdrawalEscrow withdrawalEscrow;
    uint256 sla;

    function setUp() public {
        sla = 10;
        vault = Deploy.deployL2Vault();
        withdrawalEscrow = new LockedWithdrawalEscrow(AffineVault(address(vault)), sla);
    }

    function testRegisterForWithdrawal() public {
        vm.prank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        assertEq(withdrawalEscrow.balanceOf(alice), 1000);

        vm.startPrank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), false);

        //withdrawable amount is zero due to no funds as asset
        assertEq(withdrawalEscrow.withdrawableAmount(), 0);
    }

    function testResolvePendingDebt() public {
        // do a withdrawal request
        vm.warp(1_641_070_800);
        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        //resolve pending
        withdrawalEscrow.resolveDebtShares(1000);

        vm.warp(1_641_070_900);
        changePrank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), true);

        assertEq(withdrawalEscrow.withdrawableAmount(), 0);
    }

    function testRedeemFunds() public {
        // do a withdrawal request
        vm.warp(1_641_070_800);
        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // resolve pending
        withdrawalEscrow.resolveDebtShares(1000);

        vm.warp(1_641_070_900);
        changePrank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), true);

        assertEq(withdrawalEscrow.withdrawableAmount(), 0);

        assertEq(withdrawalEscrow.redeem(), 0);
        // check balance of alice
        assertEq(withdrawalEscrow.balanceOf(alice), 0);
    }

    function testRedeemDealFunds() public {
        // do a withdrawal request
        vm.warp(1_641_070_800);
        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // resolve pending
        withdrawalEscrow.resolveDebtShares(1000);

        vm.warp(1_641_070_900);
        changePrank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), true);

        // send asset to escrow
        deal(vault.asset(), address(withdrawalEscrow), 1234);

        // check alice get the full amount
        assertEq(withdrawalEscrow.withdrawableAmount(), 1234);

        assertEq(withdrawalEscrow.redeem(), 1234);
        // check balance of alice
        assertEq(withdrawalEscrow.balanceOf(alice), 0);
    }

    function testSharedWithdawalAmount() public {
        vm.warp(1_641_070_800);
        vm.startPrank(address(vault));
        // register alice
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // register bob
        withdrawalEscrow.registerWithdrawalRequest(bob, 2000);

        withdrawalEscrow.resolveDebtShares(3000);

        // allocate funds for escrow
        deal(vault.asset(), address(withdrawalEscrow), 3000);

        vm.warp(1_641_080_800);
        changePrank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), true);
        assertEq(withdrawalEscrow.withdrawableAmount(), 1000);
        assertEq(withdrawalEscrow.redeem(), 1000);

        changePrank(bob);
        assertEq(withdrawalEscrow.canWithdraw(), true);
        assertEq(withdrawalEscrow.withdrawableAmount(), 2000);
        assertEq(withdrawalEscrow.redeem(), 2000);
    }

    function testPartialDebtClearance() public {
        vm.warp(1_641_070_800);
        vm.startPrank(address(vault));
        // register alice
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // register bob
        withdrawalEscrow.registerWithdrawalRequest(bob, 2000);

        withdrawalEscrow.resolveDebtShares(1000);

        // allocate funds for escrow
        deal(vault.asset(), address(withdrawalEscrow), 1000);

        vm.warp(1_641_080_800);
        changePrank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), true);
        assertEq(withdrawalEscrow.withdrawableAmount(), 1000);

        changePrank(bob);
        assertEq(withdrawalEscrow.canWithdraw(), false);
        assertEq(withdrawalEscrow.withdrawableAmount(), 0);
    }
}
