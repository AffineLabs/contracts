// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script} from "forge-std/Script.sol";

import {DegenVaultV2, DegenVaultV2Eth, HighYieldLpVaultEth} from "src/vaults/custom/DegenVaultV2.sol";

/* solhint-disable reason-string, no-console */

contract DeployDegen is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        new DegenVaultV2();
    }

    function runDegenEth() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        new DegenVaultV2Eth();
    }

    function runHighYieldLpEth() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        new HighYieldLpVaultEth();
    }
}
