// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

import { TwoAssetBasket } from "../TwoAssetBasket.sol";

contract L2BtcEthBasketTestFork is DSTest {
    TwoAssetBasket public basket;
    ERC20 usdc = ERC20(0x5fD6A096A23E95692E37Ec7583011863a63214AA);
    ERC20 btc = ERC20(0x1F577114D404686B47C4A739C46B8EBee7b5156F);
    ERC20 weth = ERC20(0x1F0EB2B499C51CDa602ba96013577A3887D7278D);

    function setUp() public {
        // NOTE: using mumbai addresses

        basket = new TwoAssetBasket(
            address(this), // governance
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
        emit log_named_uint("BTC PRICE: ", basket._valueOfToken(btc, 1e18));
        basket.deposit(mintAmount);
        // you receive the dollar value of the amount of btc/eth deposited into the basket
        // the testnet usdc/btc usdc/eth pools do not have accurate prices
        assertTrue(basket.balanceOf(address(this)) > 0);
        emit log_named_uint("VALUE OF VAULT", basket.valueOfVault());
        (uint256 amountInputFromBtc, uint256 amountInputFromEth) = basket._getSellDollarsByToken(5 * 1e6);
        emit log_named_uint("amountInputFromBtc,", amountInputFromBtc);
        emit log_named_uint("amountInputFromEth,", amountInputFromEth);
        emit log_named_uint("BTC received: ", btc.balanceOf(address(basket)));
        emit log_named_uint("ETH received: ", weth.balanceOf(address(basket)));

        basket.withdraw(5 * 1e6); // withdraw
    }

    function testAuction() public {}
}
