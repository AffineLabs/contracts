// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {TwoAssetBasket} from "src/vaults/TwoAssetBasket.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        TwoAssetBasket vault = new TwoAssetBasket();
        console2.log("deployer address: ", deployer);
        console2.log("new implementation address: ", address(vault));
    }
}
