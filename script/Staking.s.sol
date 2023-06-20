// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StakingExp, IBalancerVault} from "src/strategies/Staking.sol";
import {Vault} from "src/vaults/Vault.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address owner = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        StakingExp staking = new StakingExp(IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8), owner);

        require(staking.owner() == owner);
    }

    /// @notice Deploy polygon exp staking basket
    function runVault() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
        address weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;


        // Deploy implementation
        Vault impl = new Vault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, weth, "Leveraged Staked Eth", "StEthLev"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        Vault vault = Vault(address(proxy));
        require(vault.governance() == governance);
        require(vault.asset() == weth);
    }
}
