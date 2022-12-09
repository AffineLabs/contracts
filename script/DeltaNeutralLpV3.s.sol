// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {ILendingPoolAddressesProviderRegistry} from "../src/interfaces/aave.sol";

import {BaseVault} from "../src/BaseVault.sol";
import {DeltaNeutralLpV3} from "../src/both/DeltaNeutralLpV3.sol";

library SslpV3 {
    function deployPoly(BaseVault vault) internal returns (DeltaNeutralLpV3 strategy) {
        strategy = new DeltaNeutralLpV3(
        vault,
        0.05e18,
        ILendingPoolAddressesProviderRegistry(0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19),
        ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619), // weth
        AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945), // eth/usd price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608)
        );
    }

    function deployEth(BaseVault vault) internal returns (DeltaNeutralLpV3 strategy) {
        strategy = new DeltaNeutralLpV3(
        vault,
        0.05e18,
        ILendingPoolAddressesProviderRegistry(0x52D306e36E3B6B02c153d0266ff0f85d18BCD413),
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // weth
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), // eth/usd price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8) // weth/usdc pool 
        );
    }
}

contract Deploy is Script {
    function runPoly() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        SslpV3.deployPoly(BaseVault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }

    function runEth() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        SslpV3.deployEth(BaseVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9));
    }
}
