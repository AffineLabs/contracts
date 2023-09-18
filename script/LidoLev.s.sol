// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";

import {Vault} from "src/vaults/Vault.sol";
import {LidoLev} from "src/strategies/LidoLev.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        new LidoLev(LidoLev(payable(address(0))), 175, Vault(0x1196B60c9ceFBF02C9a3960883213f47257BecdB), strategists);
    }
}
