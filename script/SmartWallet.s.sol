// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {SmartWallet} from "src/utils/SmartWallet.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address rahul = 0x2033a56d6215424B3389bb863261D3B44709Fb79;
        SmartWallet wallet = new SmartWallet(rahul);
        require(wallet.hasRole(wallet.OWNER(), rahul));
    }
}
