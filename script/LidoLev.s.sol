// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console} from "forge-std/Script.sol";

import {Vault} from "src/vaults/Vault.sol";
import {LidoLev} from "src/strategies/LidoLev.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy implementation
        Vault impl = new Vault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (
                0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e,
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                "Lido leveraged staking",
                "lidoLev"
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        new LidoLev(LidoLev(payable(address(0))), 175, Vault(address(proxy)), strategists);
    }
}
