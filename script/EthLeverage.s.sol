// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {MockEpochStrategy} from "src/testnet/MockEpochStrategy.sol";

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

    function deployEthStrategyVault() internal returns (StrategyVault vault) {
        StrategyVault _vault = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (
                _getTestStrategists()[0], // TODO: check before deploy in mainnet
                _getEthMainNetWEthAddr(), // WETH
                "Affine Eth Leverage",
                "AffineEthLev"
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(_vault), initData);

        vault = StrategyVault(address(proxy));
    }

    function deployMockStrategy(StrategyVault vault) internal returns (MockEpochStrategy strategy) {
        strategy = new MockEpochStrategy(vault, _getStrategists());
    }
}

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault vault = EthLeverage.deployEthStrategyVault();

        MockEpochStrategy strategy = EthLeverage.deployMockStrategy(vault);

        vault.setStrategy(strategy);
    }
}
