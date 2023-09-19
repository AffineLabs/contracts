// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniPositionValue} from "src/interfaces/IUniPositionValue.sol";

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {ILendingPoolAddressesProviderRegistry} from "src/interfaces/aave.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {DeltaNeutralLpV3, ILendingPool} from "src/strategies/DeltaNeutralLpV3.sol";

/* solhint-disable reason-string, no-console */

library SslpV3 {
    function deployPoly(AffineVault vault) internal returns (DeltaNeutralLpV3 strategy) {
        strategy = new DeltaNeutralLpV3(
        vault,
        ILendingPool(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf),
        ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619), // weth
        AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945), // eth/usd price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608),
        IUniPositionValue(0x53dc9584bf76922E56F8bf966f34C8Ae3E5AfAF2),
        _getStrategists(),
        5714, // ~4/7
        7500 // =3/4
        );
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
    }

    /// @notice Deploy the strategy on polygon using the WMATIC/USDC pool
    function deployPolyMatic(AffineVault vault) internal returns (DeltaNeutralLpV3 strategy) {
        strategy = new DeltaNeutralLpV3(
        vault,
        ILendingPool(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf),
        ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), // WMATIC
        AggregatorV3Interface(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0), // MATIC/USD price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0xA374094527e1673A86dE625aa59517c5dE346d32), // wmatic 
        IUniPositionValue(0x53dc9584bf76922E56F8bf966f34C8Ae3E5AfAF2),
        _getStrategists(),
        5714, // ~4/7
        7500 // =3/4
        );
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
    }

    function deployEth(AffineVault vault) internal returns (DeltaNeutralLpV3 strategy) {
        strategy = new DeltaNeutralLpV3(
        vault,
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // weth
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), // eth/usd price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640), // weth/usdc pool (5 bps)
        IUniPositionValue(0xfB2DaDdd7390f7e22Db849713Ff73405c9792F69),
        _getStrategists(),
        5714, // ~4/7
        7500 // =3/4
        );
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
    }

    function deployEthWeth(AffineVault vault) internal returns (DeltaNeutralLpV3 strategy) {
        strategy = new DeltaNeutralLpV3(
        vault,
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
        ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // wbtc
        AggregatorV3Interface(0xdeb288F737066589598e9214E782fa5A8eD689e8), // btc/eth price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD), // wbtc/eth pool 
        IUniPositionValue(0xfB2DaDdd7390f7e22Db849713Ff73405c9792F69),
        _getStrategists(),
        5952, // ~25/42
        6800 // =17/25
        );
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
    }

    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function runPoly() external {
        _start();
        SslpV3.deployPoly(AffineVault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }

    function runPolyMatic() external {
        _start();
        SslpV3.deployPolyMatic(AffineVault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }

    function runEth() external {
        _start();
        SslpV3.deployEth(AffineVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9));
    }

    function runEthWeth() external {
        _start();
        address strategyAddr = address(SslpV3.deployEthWeth(AffineVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9)));
        console2.log("Eth denominated sslp uni v3 strategy addr: %s", strategyAddr);
    }
}
