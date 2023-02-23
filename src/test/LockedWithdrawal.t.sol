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

        vm.prank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), false);

        //withdrawable amount is zero due to no funds as asset
        vm.prank(alice);
        assertEq(withdrawalEscrow.withdrawableAmount(), 0);
    }

    function testResolvePendingDebt() public {
        // do a withdrawal request
        vm.warp(1_641_070_800);
        vm.prank(address(vault));
        withdrawalEscrow.registerWithdrawalRequest(alice, 1000);

        // // // resolve pending
        vm.prank(address(vault));
        withdrawalEscrow.resolveDebtToken(1000);

        vm.warp(1_641_070_900);
        vm.prank(alice);
        assertEq(withdrawalEscrow.canWithdraw(), true);

        vm.prank(alice);
        assertEq(withdrawalEscrow.withdrawableAmount(), 0);
    }
}
