// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "src/vaults/Vault.sol";

import {Base} from "./Base.sol";

/* solhint-disable reason-string, no-console */

library EthVaults {
    function deployEthWeth(address governance, address weth) internal returns (Vault) {
        // Deploy implementation
        Vault impl = new Vault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, weth, "WETH Earn Eth", "wethEarnEth"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        Vault vault = Vault(address(proxy));
        return vault;
    }
}

contract Deploy is Script, Base {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function runEthWeth() external {
        _start();
        bool testnet = vm.envBool("TEST");
        console.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));

        address governance = config.governance;
        address weth = config.weth;
        console.log("weth: %s", weth);

        Vault vault = EthVaults.deployEthWeth(governance, weth);
        console.log("Eth denominated vault addr:", address(vault));
        Vault.Number memory price = vault.detailedPrice();
        console.log("price: %s", price.num);
    }
}
