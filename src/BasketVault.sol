// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { IUniLikeSwapRouter } from "./interfaces/IUniLikeSwapRouter.sol";

contract BasketVault is ERC20 {
    address public governance;

    // The token which we take in to buy token1 and token2, e.g. USDC
    // NOTE: Assuming that inputToken is $1 for now
    // TODO: allow component tokens to be bought using any token that has a USD price oracle
    ERC20 public inputToken;
    ERC20 public token1;
    ERC20 public token2;

    // TODO: handle scenario where ratios are not 50/50
    uint256[2] public ratios;

    IUniLikeSwapRouter public uniRouter;

    constructor(
        address _governance,
        ERC20 _input,
        ERC20 _token1,
        ERC20 _token2,
        uint256[2] memory _ratios,
        IUniLikeSwapRouter _uniRouter
    ) ERC20("Alpine Large Vault Token", "AlpLarge", 18) {
        governance = _governance;
        token1 = _token1;
        token2 = _token2;
        inputToken = _input;
        ratios = _ratios;
        uniRouter = _uniRouter;
    }

    function deposit(uint256 amountInput) external {
        // Get current amounts of btc/eth (in dollars)
        (uint256 btcDollars, uint256 ethDollars) = valueOfVault();

        // swap token for ETH
        // TODO: don't allow infinite slippage. Will need price oracle of inputToken and ETH
        address[] memory path;
        path[0] = address(inputToken);
        address weth = address(token2);
        path[1] = weth;

        inputToken.transferFrom(msg.sender, address(this), amountInput);
        uint256[] memory amounts = uniRouter.swapExactTokensForTokens(
            amountInput,
            0,
            path,
            address(this),
            block.timestamp + 3 hours
        );
        uint256 amountEth = amounts[1];

        // Get dollar value of amount ETH.
        uint256 amountEthDollars = _getTokenPrice(weth) * amountEth;

        // See the docs for detailed descriptions of these 4 scenarios
        // If c_b >=  (c_e + X_prime) do nothing
        if (btcDollars >= ethDollars + amountEthDollars) return;
        // If c_b <= c_e - X_prime
        else if (btcDollars <= ethDollars - amountEthDollars) {
            // swap all ETH for BTC
            address[] memory pathSwap;
            pathSwap[0] = weth;
            pathSwap[1] = address(token1);
            uniRouter.swapExactTokensForTokens(amountEth, 0, pathSwap, address(this), block.timestamp + 3 hours);
        }
        // In these two scenarios we swap a specific amount of dollars from eth to btc by solving the following
        // c_b + swap = c_e + x_prime - swap
        else if (btcDollars >= ethDollars - amountEthDollars || btcDollars <= ethDollars + amountEthDollars) {
            uint256 amountSwapDollars = (ethDollars - btcDollars + amountEthDollars) / 2;
            uint256 amountSwapEth = amountSwapDollars / _getTokenPrice(weth);
            address[] memory pathSwap;
            pathSwap[0] = weth;
            pathSwap[1] = address(token1);
            uniRouter.swapExactTokensForTokens(amountSwapEth, 0, pathSwap, address(this), block.timestamp + 3 hours);
        }
    }

    function _getTokenPrice(address token) internal view returns (uint256) {
        // TODO: make sure the units match we would expect, go through every invocation of this
    }

    function valueOfVault() public view returns (uint256, uint256) {
        uint256 btcBal = token1.balanceOf(address(this));
        uint256 ethBal = token2.balanceOf(address(this));

        uint256 btcDollars = btcBal * _getTokenPrice(address(token1));
        uint256 ethDollars = ethBal * _getTokenPrice(address(token2));
        return (btcDollars, ethDollars);
    }

    function withdraw(uint256 dollarAmount) external {}
}
