// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { IUniLikeSwapRouter } from "./interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";

contract BasketVault is ERC20 {
    address public governance;

    // The token which we take in to buy token1 and token2, e.g. USDC
    // NOTE: Assuming that inputToken is $1 for now
    // TODO: allow component tokens to be bought using any token that has a USD price oracle
    ERC20 public inputToken;
    ERC20 public token1;
    ERC20 public token2;

    uint256[2] public ratios;

    IUniLikeSwapRouter public uniRouter;

    // These must be USD price feeds for token1 and token2
    AggregatorV3Interface public priceFeed1;
    AggregatorV3Interface public priceFeed2;

    constructor(
        address _governance,
        ERC20 _input,
        ERC20 _token1,
        ERC20 _token2,
        uint256[2] memory _ratios,
        IUniLikeSwapRouter _uniRouter,
        AggregatorV3Interface _priceFeed1,
        AggregatorV3Interface _priceFeed2
    ) ERC20("Alpine Large Vault Token", "AlpLarge", 18) {
        governance = _governance;
        token1 = _token1;
        token2 = _token2;
        inputToken = _input;
        ratios = _ratios;
        uniRouter = _uniRouter;
        priceFeed1 = _priceFeed1;
        priceFeed2 = _priceFeed2;

        // Allow uniRouter to spend all tokens that we may swap
        inputToken.approve(address(uniRouter), type(uint256).max);
        token1.approve(address(uniRouter), type(uint256).max);
        token2.approve(address(uniRouter), type(uint256).max);
    }

    function deposit(uint256 amountInput) external {
        // Get current amounts of btc/eth (in dollars)
        (uint256 btcDollars, uint256 ethDollars) = valueOfVault();

        // We do two swaps. The amount of dollars we swap to each coin is determined by the ratios given above
        // If the ratios were floats, we would do r_1 * amountInput to get the amount of `inputToken` to swap to btc
        // But since we're using ints we do r1 * amountInput / (r1 + r2)

        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);
        uint256 amountInputToBtc = (r1 * amountInput) / (r1 + r2);
        uint256 amountInputToEth = amountInput - amountInputToBtc;

        // TODO: don't allow infinite slippage. Will need price oracle of inputToken and ETH
        inputToken.transferFrom(msg.sender, address(this), amountInput);
        address[] memory pathBtc;
        pathBtc[0] = address(inputToken);
        pathBtc[1] = address(token1);

        address[] memory pathEth;
        pathEth[0] = address(inputToken);
        pathEth[1] = address(token2);

        uint256[] memory btcAmounts = uniRouter.swapExactTokensForTokens(
            amountInputToBtc,
            0,
            pathBtc,
            address(this),
            block.timestamp + 3 hours
        );

        uint256[] memory ethAmounts = uniRouter.swapExactTokensForTokens(
            amountInputToEth,
            0,
            pathEth,
            address(this),
            block.timestamp + 3 hours
        );

        uint256 btcReceived = btcAmounts[1];
        uint256 ethReceived = ethAmounts[1];

        uint256 dollarsReceived = _valueOfToken(token1, btcReceived) + _valueOfToken(token2, ethReceived);

        // Issue shares based on dollar amounts of user coins vs total holdings of the vault
        uint256 numShares = (dollarsReceived * totalSupply) / (btcDollars + ethDollars);
        _mint(msg.sender, numShares);
    }

    function _getTokenPrice(ERC20 token) internal view returns (uint256) {
        // NOTE: Chainlink price feeds report prices of the "base unit" of your token. So
        // we receive the price of 1 ether (1e18 wei). The price also comes with its own decimals. E.g. a price
        // of $1 with 8 decimals is given as 1e8.
        // TODO: make sure the units match we would expect, go through every invocation of this
        AggregatorV3Interface feed;
        if (token == token1) {
            feed = priceFeed1;
        } else {
            feed = priceFeed2;
        }
        (, int256 price, , , ) = feed.latestRoundData();
        return uint256(price);
    }

    function _valueOfToken(ERC20 token, uint256 amount) internal view returns (uint256) {
        // Convert tokens to dollars using as many decimal places as the price feed gives us
        // e.g. Say ether is $1. If the price feed uses 8 decimals then a price of $1 is 1e8.
        // If we have 2 ether then return 2 * 1e8 as the dollar value of our balance

        // NOTE: All Chainlink USD price feeds use 8 decimals, so all invocations of this function
        // should return a dollar amount with the number of decimals.

        return (amount * _getTokenPrice(token)) / token.decimals();
    }

    function valueOfVault() public view returns (uint256, uint256) {
        uint256 btcBal = token1.balanceOf(address(this));
        uint256 ethBal = token2.balanceOf(address(this));

        uint256 btcDollars = _valueOfToken(token1, btcBal);
        uint256 ethDollars = _valueOfToken(token2, ethBal);
        return (btcDollars, ethDollars);
    }

    function withdraw(uint256 amountInput) external returns (uint256 dollarsLiquidated) {
        // Try to get `amountInput` of `inputToken` out of vault

        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);
        uint256 amountInputFromBtc = (r1 * amountInput) / (r1 + r2);
        uint256 amountInputFromEth = amountInput - amountInputFromBtc;

        // Get desired amount of inputToken from eth and btc reserves
        address[] memory path;
        path[0] = address(token1);
        path[1] = address(inputToken);

        uint256[] memory btcAmounts = uniRouter.swapTokensForExactTokens(
            amountInputFromBtc,
            type(uint256).max,
            path,
            address(this),
            block.timestamp + 3 hours
        );
        uint256[] memory ethAmounts = uniRouter.swapTokensForExactTokens(
            amountInputFromEth,
            type(uint256).max,
            path,
            address(this),
            block.timestamp + 3 hours
        );

        uint256 btcSent = btcAmounts[0];
        uint256 ethSent = ethAmounts[0];

        // NOTE: The user eats the slippage and trading fees. E.g. if you get $10 out but we spend $12 of collateral
        // to give that to the user, we still burn $12 of shares

        dollarsLiquidated = _valueOfToken(token1, btcSent) + _valueOfToken(token2, ethSent);
        // TODO: Remove assumption that inputToken is equal to one dollar

        // Get share/dollar ratio (`shares_per_dollar`)
        // Calculate number of shares to burn with numShares = dollarAmount * shares_per_dollar
        // Try to burn numShares, will revert if user does not have enough
        (uint256 btcDollars, uint256 ethDollars) = valueOfVault();
        uint256 numShares = (dollarsLiquidated * totalSupply) / (btcDollars + ethDollars);

        _burn(msg.sender, numShares);
    }
}
