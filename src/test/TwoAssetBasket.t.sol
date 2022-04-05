// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { DSTestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/src/stdlib.sol";
import { Deploy } from "./Deploy.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { Dollar } from "../DollarMath.sol";
import { TwoAssetBasket } from "../TwoAssetBasket.sol";

contract L2BtcEthBasketTestFork is DSTestPlus {
    TwoAssetBasket public basket;
    ERC20 usdc = ERC20(0x8f7116CA03AEB48547d0E2EdD3Faa73bfB232538);
    ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
    ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);

    function setUp() public {
        // NOTE: using mumbai addresses

        basket = new TwoAssetBasket(
            address(this), // governance
            address(0), // forwarder
            10_000 * 1e6, // once the vault is $10,000 out of balance then we can rebalance
            5_000 * 1e6, // selling in $5,000 blocks
            IUniLikeSwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
            usdc, // mintable usdc
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

    function testDepositWithdraw() public {
        // mint some usdc, can remove hardcoded selector later
        uint256 mintAmount = 100 * 1e6;
        bytes memory mintData = abi.encodeWithSelector(0x40c10f19, address(this), mintAmount);
        address(usdc).call(mintData);
        assertEq(usdc.balanceOf(address(this)), mintAmount);

        usdc.approve(address(basket), type(uint256).max);
        basket.deposit(mintAmount);

        // you receive the dollar value of the amount of btc/eth deposited into the basket
        // the testnet usdc/btc usdc/eth pools do not have accurate prices
        assertTrue(basket.balanceOf(address(this)) > 0);
        emit log_named_uint("VALUE OF VAULT", Dollar.unwrap(basket.valueOfVault()));

        uint256 inputReceived = basket.withdraw(55 * 1e6);
        emit log_named_uint("DOLLARS WITHDRAWN: ", inputReceived);
    }

    function testAuction() public {}
}
