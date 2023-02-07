// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {BaseVault} from "../src/BaseVault.sol";
import {DeltaNeutralLp, ILendingPool} from "../src/both/DeltaNeutralLp.sol";
import {IMasterChef} from "../src/interfaces/sushiswap/IMasterChef.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

library Sslp {
    /// @dev WETH/USDC on polygon
    function deployPoly(BaseVault vault) internal returns (DeltaNeutralLp strategy) {
        strategy = new DeltaNeutralLp(
        vault,
        ILendingPool(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf),
        ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
        AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945),
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
        IMasterChef(0x0769fd68dFb93167989C6f7254cd0D766Fb2841F), // MasterChef
        1, // Masterchef PID
        true, // use MasterChefV2 interface
        ERC20(0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a),
        IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608),
        _getStrategists()
        );
    }

    function _getStrategists() internal view returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    /// @dev WETH/USDC on sushiswap
    function deployEth(BaseVault vault) internal returns (DeltaNeutralLp strategy) {
        strategy = new DeltaNeutralLp(
        vault,
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // weth
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), // eth-usdc feed
        IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F),
        IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd), // MasterChef
        1, // Masterchef PID for WETH/USDC
        false, // use MasterChefV2 interface
        ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2),
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640), // 5 bps pool (gets most volume)
        _getStrategists()
        );
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function runPoly() external {
        _start();
        Sslp.deployPoly(BaseVault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }

    function runEth() external {
        _start();
        Sslp.deployEth(BaseVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9));
    }
}
