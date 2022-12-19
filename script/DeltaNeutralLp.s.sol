// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {BaseVault} from "../src/BaseVault.sol";
import {DeltaNeutralLp, ILendingPoolAddressesProviderRegistry} from "../src/both/DeltaNeutralLp.sol";
import {IMasterChef} from "../src/interfaces/sushiswap/IMasterChef.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

library Sslp {
    function deployPoly(BaseVault vault) internal returns (DeltaNeutralLp strategy) {
        strategy = new DeltaNeutralLp(
        vault,
        0.001e18,
        ILendingPoolAddressesProviderRegistry(0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19),
        ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
        AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945),
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
        IMasterChef(0x0769fd68dFb93167989C6f7254cd0D766Fb2841F), // MasterChef
        1, // Masterchef PID
        true, // use MasterChefV2 interface
        ERC20(0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a)
        );
    }
}

contract Deploy is Script {
    function runPoly() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        Sslp.deployPoly(BaseVault(0x829363736a5A9080e05549Db6d1271f070a7e224));
    }
}
