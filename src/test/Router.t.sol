// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { TwoAssetBasket } from "../polygon/TwoAssetBasket.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { Deploy } from "./Deploy.sol";
import { ERC4626Router } from "../polygon/ERC4626Router.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

contract L2RouterTestFork is TestPlus {
    MockERC20 token;
    L2Vault vault;
    ERC4626Router router;
    TwoAssetBasket basket;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        token = MockERC20(0x8f7116CA03AEB48547d0E2EdD3Faa73bfB232538);
        router = new ERC4626Router("");
        ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
        ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);
        basket = new TwoAssetBasket(
            address(this), // governance,
            address(0), // forwarder
            10_000 * 1e6, // once the vault is $10,000 out of balance then we can rebalance
            5_000 * 1e6, // selling in $5,000 blocks
            IUniLikeSwapRouter(address(0)), // sushiswap router
            token, // mintable usdc
            // WBTC AND WETH
            [btc, weth],
            [uint256(1), uint256(1)], // ratios (basket should contain an equal amount of btc/eth)
            // Price feeds (BTC/USD and ETH/USD)
            [
                AggregatorV3Interface(0x007A22900a3B98143368Bd5906f8E17e9867581b),
                AggregatorV3Interface(0x0715A7794a1dc8e42615F059dD6e406A6594651A)
            ]
        );
    }

    function testMultipleDeposits() public {
        address user = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        token.mint(address(user), 10e6);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(router.depositToVault.selector, IERC4626(address(basket)), user, 1e6, 0);
        data[1] = abi.encodeWithSelector(router.depositToVault.selector, IERC4626(address(vault)), user, 1e6, 0);
        vm.startPrank(user);
        token.approve(address(router), 2e6);
        router.approve(token, address(vault), 1e6);
        router.multicall(data);
        assert(vault.balanceOf(user) == 1e6);
        assert(basket.balanceOf(user) > 0);
    }
}
