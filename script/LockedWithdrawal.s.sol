// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {LockedWithdrawalEscrow} from "src/vaults/LockedWithdrawalEscrow.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {Vault} from "src/vaults/Vault.sol";

/* solhint-disable reason-string */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        Vault vault = new Vault();
        LockedWithdrawalEscrow escrow = new LockedWithdrawalEscrow(vault, 24 hours);
        require(escrow.vault() == vault);
    }
}
