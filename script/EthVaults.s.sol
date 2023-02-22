// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "src/vaults/Vault.sol";

library EthVaults {
    function deployEthWeth() internal returns (Vault) {
        // Deploy implementation
        Vault impl = new Vault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (
                0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e, /* governance */
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, /* weth */
                "wETH Earn Eth",
                "wEthEarnEth"
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        Vault vault = Vault(address(proxy));
        return vault;
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function runEthWeth() external {
        _start();
        console.log("Eth denominated vault addr:", address(EthVaults.deployEthWeth()));
    }
}
