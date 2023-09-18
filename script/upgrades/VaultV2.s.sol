// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {VaultV2} from "src/vaults/VaultV2.sol";
import {EthVaultV2} from "src/vaults/EthVaultV2.sol";

/* solhint-disable reason-string, no-console */

contract LevStakingV2Poly is VaultV2 {}

contract LevStakingV2Eth is EthVaultV2 {}

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        LevStakingV2Poly vault = new LevStakingV2Poly();
        console2.log("new implementation address: ", address(vault));
    }

    function runEth() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        LevStakingV2Eth vault = new LevStakingV2Eth();
        console2.log("new implementation address: ", address(vault));
    }
}
