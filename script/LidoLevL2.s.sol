// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Vault} from "src/vaults/Vault.sol";
import {EthVaultV2} from "src/vaults/EthVaultV2.sol";

/* solhint-disable reason-string, no-console */

contract LevStakingPolygon is EthVaultV2 {}

contract DeployBase is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        LevStakingPolygon impl = new LevStakingPolygon();

        address governance = 0x535B06019dD972Cd48655F5838306dfF8E68d6FD;
        address asset = 0x4200000000000000000000000000000000000006;

        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(Vault.initialize, (governance, asset, "Base Leveraged cbEth Staking", "BaseLevCbStEth"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        LevStakingPolygon vault = LevStakingPolygon(payable(address(proxy)));
        require(vault.governance() == governance);
        require(vault.asset() == asset);
    }

    function runGoerli() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        LevStakingPolygon impl = new LevStakingPolygon();

        address governance = 0x69b3ce79B05E57Fc31156fEa323Bd96E6304852D;
        address asset = 0x4200000000000000000000000000000000000006;

        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(Vault.initialize, (governance, asset, "Base Leveraged cbEth Staking", "BaseLevCbStEth"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        LevStakingPolygon vault = LevStakingPolygon(payable(address(proxy)));
        require(vault.governance() == governance);
        require(vault.asset() == asset);
    }
}
