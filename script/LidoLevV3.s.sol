// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";

import {Vault, AffineVault} from "src/vaults/Vault.sol";
import {LidoLevV3} from "src/strategies/LidoLevV3.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        console2.log("deployer %s", deployer);
        vm.startBroadcast(deployer);
    }

    function run() external {
        _start();

        Vault vault = Vault(0xF5c10746B8EE6B69A17f66eCD642d2Fb9df8fcE0); // tmp vault add
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;

        LidoLevV3 strategy = new LidoLevV3(AffineVault(address(vault)), strategists);

        console2.log("strategy add %s", address(strategy));

        require(address(vault.asset()) == address(strategy.asset()), "Error: Vault asset mismatch detected.");
        require(
            address(strategy.asset()) == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "Error: Asset mismatch detected."
        );
    }
}
