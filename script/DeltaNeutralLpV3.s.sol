// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {ILendingPoolAddressesProviderRegistry} from "../src/interfaces/aave.sol";

import {L2Vault} from "../src/polygon/L2Vault.sol";
import {DeltaNeutralLpV3} from "../src/polygon/DeltaNeutralLpV3.sol";

library SslpV3 {
    function deploy(L2Vault vault) internal returns (DeltaNeutralLpV3 strategy) {
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
}

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        SslpV3.deploy(L2Vault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }
}
