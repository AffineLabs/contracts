// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* solhint-disable reason-string, no-console */

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {EthVault} from "src/vaults/EthVault.sol";
import {Vault} from "src/vaults/Vault.sol";
import {MockEpochStrategy} from "src/testnet/MockEpochStrategy.sol";
import {Base} from "./Base.sol";

library EthLeverage {
    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    function _getTestStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }

    function _getEthMainNetUSDCAddr() internal pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _getEthMainNetWEthAddr() internal pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function deployEthVault(address governance) internal returns (EthVault vault) {
        EthVault _vault = new EthVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (
                governance, // TODO: check before deploy in mainnet
                _getEthMainNetWEthAddr(), // WETH
                "Affine Staked Eth Leverage",
                "AffineStEthLev"
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(_vault), initData);

        vault = EthVault(payable(address(proxy)));
    }
}

contract Deploy is Script, Base {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("deployer address %s", deployer);
    }

    function run() external {
        bool testnet = vm.envBool("TEST");
        console2.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));

        address governance = config.governance;

        console2.log("governance %s", governance);
        _start();

        EthVault vault = EthLeverage.deployEthVault(governance);

        console2.log("vault address %s", address(vault));
    }
}
