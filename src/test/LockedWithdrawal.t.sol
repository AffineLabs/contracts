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
    uint256 blockStartTime;

    function setUp() public {
        sla = 10;
        blockStartTime = 100;
        vault = Deploy.deployL2Vault();
        withdrawalEscrow = new LockedWithdrawalEscrow(AffineVault(address(vault)), sla);
    }

    function testRegisterForWithdrawal() public {
        vm.prank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        assertEq(withdrawalEscrow.balanceOf(alice), 1000);

        assertEq(withdrawalEscrow.canWithdraw(alice), false);

        //withdrawable amount is zero due to no funds as asset
        assertEq(withdrawalEscrow.withdrawableAmount(alice), 0);
    }

    function testResolvePendingDebt() public {
        // do a withdrawal request
        vm.warp(blockStartTime);
        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        //resolve pending
        withdrawalEscrow.resolveDebtShares(1000);

        vm.warp(blockStartTime + sla);

        assertEq(withdrawalEscrow.canWithdraw(alice), true);

        assertEq(withdrawalEscrow.withdrawableAmount(alice), 0);
    }

    function testRedeemFunds() public {
        // do a withdrawal request
        vm.warp(blockStartTime);

        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // resolve pending
        withdrawalEscrow.resolveDebtShares(1000);

        vm.warp(blockStartTime + sla);

        assertEq(withdrawalEscrow.canWithdraw(alice), true);

        assertEq(withdrawalEscrow.withdrawableAmount(alice), 0);

        vm.startPrank(alice);
        assertEq(withdrawalEscrow.redeem(), 0);
        // check balance of alice
        assertEq(withdrawalEscrow.balanceOf(alice), 0);
    }

    function testRedeemDealFunds() public {
        // do a withdrawal request
        vm.warp(blockStartTime);

        vm.startPrank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // resolve pending
        withdrawalEscrow.resolveDebtShares(1000);

        vm.warp(blockStartTime + sla);

        assertEq(withdrawalEscrow.canWithdraw(alice), true);

        // send asset to escrow
        deal(vault.asset(), address(withdrawalEscrow), 1234);

        // check alice get the full amount
        assertEq(withdrawalEscrow.withdrawableAmount(alice), 1234);

        vm.startPrank(alice);
        assertEq(withdrawalEscrow.redeem(), 1234);
        // check balance of alice
        assertEq(withdrawalEscrow.balanceOf(alice), 0);
    }

    function testSharedWithdawalAmount() public {
        vm.warp(blockStartTime);

        vm.startPrank(address(vault));
        // register alice
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // register bob
        withdrawalEscrow.registerWithdrawalRequest(bob, 2000);

        withdrawalEscrow.resolveDebtShares(3000);

        // allocate funds for escrow
        deal(vault.asset(), address(withdrawalEscrow), 3000);

        vm.warp(blockStartTime + sla);

        assertEq(withdrawalEscrow.canWithdraw(alice), true);
        assertEq(withdrawalEscrow.withdrawableAmount(alice), 1000);

        vm.startPrank(alice);
        assertEq(withdrawalEscrow.redeem(), 1000);

        assertEq(withdrawalEscrow.canWithdraw(bob), true);
        assertEq(withdrawalEscrow.withdrawableAmount(bob), 2000);
        vm.startPrank(bob);
        assertEq(withdrawalEscrow.redeem(), 2000);
    }

    function testPartialDebtClearance() public {
        vm.warp(blockStartTime);
        vm.startPrank(address(vault));
        // register alice
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // register bob
        withdrawalEscrow.registerWithdrawalRequest(bob, 2000);

        withdrawalEscrow.resolveDebtShares(1000);

        // allocate funds for escrow
        deal(vault.asset(), address(withdrawalEscrow), 1000);

        vm.warp(blockStartTime + sla);

        assertEq(withdrawalEscrow.canWithdraw(alice), true);
        assertEq(withdrawalEscrow.withdrawableAmount(alice), 1000);

        assertEq(withdrawalEscrow.canWithdraw(bob), false);
        assertEq(withdrawalEscrow.withdrawableAmount(bob), 0);
    }

    function testTransferDebtToken() public {
        vm.warp(blockStartTime);
        vm.startPrank(address(vault));
        // register alice
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // register bob
        withdrawalEscrow.registerWithdrawalRequest(bob, 2000);

        withdrawalEscrow.resolveDebtShares(3000);

        // allocate funds for escrow
        deal(vault.asset(), address(withdrawalEscrow), 3000);

        vm.warp(blockStartTime + sla);

        // transfer funds to alice
        vm.startPrank(alice);
        withdrawalEscrow.transfer(bob, 1000);

        // should not change anything
        assertEq(withdrawalEscrow.canWithdraw(alice), true);
        assertEq(withdrawalEscrow.withdrawableAmount(alice), 1000);

        assertEq(withdrawalEscrow.canWithdraw(bob), true);
        assertEq(withdrawalEscrow.withdrawableAmount(bob), 2000);
    }
}
