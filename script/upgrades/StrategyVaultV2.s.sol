// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {StrategyVaultV2} from "src/vaults/locked/StrategyVaultV2.sol";

contract DegenVaultV2 is StrategyVaultV2 {
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 10;
    }
}


contract DeployDegen is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        DegenVaultV2 vault = new DegenVaultV2();
        console.log("new implementation address: ", address(vault));
    }
}