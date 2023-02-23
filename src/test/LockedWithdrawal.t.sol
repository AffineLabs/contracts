// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";
import {Deploy} from "./Deploy.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {LockedWithdrawalEscrow} from "src/vaults/LockedWithdrawal.sol";

contract LockedWithdrawalTest is TestPlus {
    BaseVault vault;

    LockedWithdrawalEscrow withdrawalEscrow;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        withdrawalEscrow = new LockedWithdrawalEscrow(AffineVault(address(vault)), 10);
    }
}
