// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {Vault} from "src/vaults/Vault.sol";

/* solhint-disable reason-string, no-console */

contract BaseLevEthVault is VaultV2 {}


contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }


    function deployBoostedEth() public {
        _start();
        // Deploy implementation
        BaseLevEthVault impl = new BaseLevEthVault();

        address governance = 0x535B06019dD972Cd48655F5838306dfF8E68d6FD;
        address asset = 0x4200000000000000000000000000000000000006; // WETH

        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(Vault.initialize, (governance, asset, "Affine Staked Eth Leverage", "BaseEthLev"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        BaseLevEthVault vault = BaseLevEthVault(address(proxy));
        require(vault.governance() == governance);
        require(address(vault.asset()) == asset);

        console2.log("detailed price %s", vault.detailedPrice().num);
        console2.log("Vault address %s", address(vault));
    }
}
