// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {DeltaNeutralLp, ILendingPool} from "src/strategies/DeltaNeutralLp.sol";
import {LenderInfo, LpInfo, LendingParam} from "src/strategies/DeltaNeutralLp.sol";
import {IMasterChef} from "src/interfaces/sushiswap/IMasterChef.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

library Sslp {
    /// @dev WETH/USDC on polygon
    function deployPoly(AffineVault vault) internal returns (DeltaNeutralLp strategy) {
        strategy = new DeltaNeutralLp(
        vault,
        LenderInfo({
            pool: ILendingPool(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf),
            borrow: ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
            priceFeed: AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945)
        }),
        LpInfo({
            router: IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
            masterChef: IMasterChef(0x0769fd68dFb93167989C6f7254cd0D766Fb2841F), // MasterChef
            masterChefPid: 1, // Masterchef PID
            useMasterChefV2: true, // use MasterChefV2 interface
            sushiToken: ERC20(0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a)
        }),
        IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608),
        _getStrategists()
        );
    }

    function _getStrategists() internal view returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    /// @dev WETH/USDC on sushiswap
    function deployEth(AffineVault vault) internal returns (DeltaNeutralLp strategy) {
        strategy = new DeltaNeutralLp(
        vault,
        LenderInfo({
            pool: ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
            borrow: ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // weth
            priceFeed: AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419) // eth-usdc feed
        }),
        LpInfo({
            router: IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F),
            masterChef: IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd), // MasterChef
            masterChefPid: 1, // Masterchef PID for WETH/USDC
            useMasterChefV2: false, // use MasterChefV2 interface
            sushiToken: ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2)
        }),
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
        Sslp.deployPoly(AffineVault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }

    function runEth() external {
        _start();
        Sslp.deployEth(AffineVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9));
    }
}
