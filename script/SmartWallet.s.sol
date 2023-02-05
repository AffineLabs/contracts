// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {SmartWallet} from "../src/both/SmartWallet.sol";

/* solhint-disable reason-string */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        SmartWallet wallet = new SmartWallet(deployer);
        require(wallet.hasRole(wallet.OWNER(), deployer));
    }
}
