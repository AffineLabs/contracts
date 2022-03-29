// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";

import { IUniLikeSwapRouter } from "./interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";

contract TwoAssetBasket is ERC20, BaseRelayRecipient {
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
        address forwarder,
        uint256 _rebalanceDelta,
        uint256 _blockSize,
        IUniLikeSwapRouter _uniRouter,
        ERC20 _input,
        ERC20[2] memory _tokens,
        uint256[2] memory _ratios,
        AggregatorV3Interface[2] memory _priceFeeds
    ) ERC20("Alpine Large Vault Token", "alpLarge", 18) {
        require(_rebalanceDelta >= _blockSize, "DELTA_TOO_SMALL");
        governance = _governance;
        _setTrustedForwarder(forwarder);
        rebalanceDelta = _rebalanceDelta;
        blockSize = _blockSize;
        (token1, token2) = (_tokens[0], _tokens[1]);
        inputToken = _input;
        ratios = _ratios;
        uniRouter = _uniRouter;
        (priceFeed1, priceFeed2) = (_priceFeeds[0], _priceFeeds[1]);

        // Allow uniRouter to spend all tokens that we may swap
        inputToken.approve(address(uniRouter), type(uint256).max);
        token1.approve(address(uniRouter), type(uint256).max);
        token2.approve(address(uniRouter), type(uint256).max);
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }

    /** DEPOSIT / WITHDRAW
     **************************************************************************/
    event Deposit(address indexed owner, uint256 tokenAmount, uint256 shareAmount);

    function deposit(uint256 amountInput) external {
        // Get current amounts of btc/eth (in dollars)
        uint256 vaultDollars = valueOfVault();

        // We do two swaps. The amount of dollars we swap to each coin is determined by the ratios given above
        // See the whitepaper for the derivation of these amounts

        // Get dollar amounts of btc and eth to buy
        (uint256 amountInputToBtc, uint256 amountInputToEth) = _getBuyDollarsByToken(amountInput);

        // TODO: don't allow infinite slippage. Will need price oracle of inputToken and ETH
        inputToken.transferFrom(_msgSender(), address(this), amountInput);
        address[] memory pathBtc = new address[](2);
        pathBtc[0] = address(inputToken);
        pathBtc[1] = address(token1);

        address[] memory pathEth = new address[](2);
        pathEth[0] = address(inputToken);
        pathEth[1] = address(token2);

        uint256[] memory btcAmounts = uniRouter.swapExactTokensForTokens(
            amountInputToBtc,
            0,
            pathBtc,
            address(this),
            block.timestamp
        );

        uint256[] memory ethAmounts = uniRouter.swapExactTokensForTokens(
            amountInputToEth,
            0,
            pathEth,
            address(this),
            block.timestamp
        );

        uint256 btcReceived = btcAmounts[1];
        uint256 ethReceived = ethAmounts[1];

        uint256 dollarsReceived = _valueOfToken(token1, btcReceived) + _valueOfToken(token2, ethReceived);

        // Issue shares based on dollar amounts of user coins vs total holdings of the vault
        uint256 numShares;
        if (totalSupply == 0) {
            numShares = dollarsReceived;
        } else {
            numShares = (dollarsReceived * totalSupply) / vaultDollars;
        }

        emit Deposit(_msgSender(), amountInput, numShares);
        _mint(_msgSender(), numShares);
    }

    event Withdraw(address indexed owner, uint256 tokenAmount, uint256 shareAmount);

    function withdraw(uint256 amountInput) external returns (uint256 dollarsReceived) {
        // Try to get `amountInput` of `inputToken` out of vault

        uint256 vaultDollars = valueOfVault();

        // Get dollar amounts of btc and eth to sell
        (uint256 amountInputFromBtc, uint256 amountInputFromEth) = _getSellDollarsByToken(amountInput);

        // Get desired amount of inputToken from eth and btc reserves
        address[] memory pathBtc = new address[](2);
        pathBtc[0] = address(token1);
        pathBtc[1] = address(inputToken);

        address[] memory pathEth = new address[](2);
        pathEth[0] = address(token2);
        pathEth[1] = address(inputToken);

        if (amountInputFromBtc > 0) {
            uint256[] memory btcAmounts = uniRouter.swapExactTokensForTokens(
                _tokensFromDollars(token1, amountInputFromBtc),
                0,
                pathBtc,
                address(this),
                block.timestamp
            );
            dollarsReceived += btcAmounts[1];
        }

        if (amountInputFromEth > 0) {
            uint256[] memory ethAmounts = uniRouter.swapExactTokensForTokens(
                _tokensFromDollars(token2, amountInputFromEth),
                0,
                pathEth,
                address(this),
                block.timestamp
            );
            dollarsReceived += ethAmounts[1];
        }

        // NOTE: The user eats the slippage and trading fees. E.g. if you request $10 you may only get $9 out
        // TODO: Remove assumption that inputToken is equal to one dollar

        // Calculate number of shares to burn with numShares = dollarAmount * shares_per_dollar
        // Try to burn numShares, will revert if user does not have enough

        // NOTE: Even if dollarsReceived > amountInput, the vault only sold $amountInput worth of assets
        // (according to chainlink). The share price is a chainlink price, and so the user can at most be asked to
        // burn $amountInput worth of shares
        uint256 numShares = (amountInput * totalSupply) / vaultDollars;

        _burn(_msgSender(), numShares);

        emit Withdraw(_msgSender(), amountInput, numShares);
        inputToken.transfer(_msgSender(), dollarsReceived);
    }

    /** EXCHANGE RATES
     **************************************************************************/
    // When depositing, determing amount of input token that should be used to buy BTC and ETH
    // respectively
    function _getBuyDollarsByToken(uint256 amountInput) internal view returns (uint256, uint256) {
        (uint256 btcDollars, uint256 ethDollars) = _valueOfVaultComponents();
        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);

        uint256 a = (r1 * (ethDollars + amountInput)) / (r1 + r2);
        uint256 b = (r2 * btcDollars) / (r1 + r2);

        // We want to buy a negative amount of btc. Just spend all of input token on eth.
        if (b > a) return (0, amountInput);

        // We want to buy btc with more of inputToken than we have. Cap the dollars going to btc
        uint256 amountInputToBtc = a - b;
        if (amountInputToBtc > amountInput) return (amountInput, 0);

        // The regular case where we split the input. Some amount of money goes to btc, the rest goes to eth
        uint256 amountInputToEth = amountInput - amountInputToBtc;
        return (amountInputToBtc, amountInputToEth);
    }

    function _getSellDollarsByToken(uint256 amountInput) public view returns (uint256, uint256) {
        (uint256 btcDollars, uint256 ethDollars) = _valueOfVaultComponents();
        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);

        uint256 a = (r2 * btcDollars) / (r1 + r2);
        uint256 b = (r1 * (ethDollars - amountInput)) / (r1 + r2);

        // A negative amount of the liquidation should come from btc (we want to buy btc)
        if (b > a) return (0, amountInput);

        // Cap the amount that we attempt to liquidate from btc
        uint256 amountInputFromBtc = a - b;
        if (amountInputFromBtc > amountInput) return (amountInput, 0);

        // The regular case where we split the input. Some amount of money comes from btc, the rest goes comes from eth
        uint256 amountInputFromEth = amountInput - amountInputFromBtc;
        return (amountInputFromBtc, amountInputFromEth);
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

    function valueOfVault() public view returns (uint256) {
        (uint256 btcDollars, uint256 ethDollars) = _valueOfVaultComponents();
        return btcDollars + ethDollars;
    }

    function _valueOfVaultComponents() internal view returns (uint256, uint256) {
        uint256 btcBal = token1.balanceOf(address(this));
        uint256 ethBal = token2.balanceOf(address(this));

        uint256 btcDollars = _valueOfToken(token1, btcBal);
        uint256 ethDollars = _valueOfToken(token2, ethBal);
        return (btcDollars, ethDollars);
    }

    function _valueOfToken(ERC20 token, uint256 amount) public view returns (uint256) {
        // Convert tokens to dollars using as many decimal places as the price feed gives us
        // e.g. Say ether is $1. If the price feed uses 8 decimals then a price of $1 is 1e8.
        // If we have 2 ether then return 2 * 1e8 as the dollar value of our balance

        // NOTE: All Chainlink USD price feeds use 8 decimals, so all invocations of this function
        // should return a dollar amount with the same number of decimals.

        return (amount * _getTokenPrice(token)) / (10**token.decimals());
    }

    function _tokensFromDollars(ERC20 token, uint256 amountDollars) internal view returns (uint256) {
        // Convert dollars to tokens with token's amount of decimals
        uint256 oneToken = 10**token.decimals();
        return (amountDollars * oneToken) / _getTokenPrice(token);
    }

    /** AUCTIONS
     **************************************************************************/

    /// @notice The amount (in dollars that one token must be above its ideal amount before we begin to auction it off)
    uint256 rebalanceDelta;

    /// @notice Is the auction active
    bool public isRebalancing;

    /// @notice The size of each rebalancing trade
    /// @dev This should be smaller than the rebalance delta
    uint256 blockSize;
    /// @notice The number of blocks left to sell in the current rebalance
    uint256 numBlocksLeftToSell;
    /// @notice Whether we are selling token1 or token2 (btc or eth)
    ERC20 tokenToSell;

    /// @notice Initiate the auction. This can be done by anyone since it will only proceed if
    /// vault is significantly imbalanced
    function startRebalance() external {
        (bool needRebalance, uint256 numBlocks, ERC20 _tokenToSell) = _isImbalanced();
        if (!needRebalance) return;
        isRebalancing = true;
        numBlocksLeftToSell = numBlocks;
        tokenToSell = _tokenToSell;
    }

    function _isImbalanced()
        internal
        view
        returns (
            bool imbalanced,
            uint256 numBlocks,
            ERC20 _tokenToSell
        )
    {
        (uint256 btcDollars, uint256 ethDollars) = _valueOfVaultComponents();
        uint256 vaultDollars = btcDollars + ethDollars;

        // See how far we are from ideal amount of Eth/Btc
        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);
        uint256 idealDollarsOfEth = (r2 * vaultDollars) / (r1 + r2);
        uint256 idealDollarsOfBtc = vaultDollars - idealDollarsOfEth;

        if (ethDollars > idealDollarsOfEth + rebalanceDelta) {
            imbalanced = true;
            numBlocks = (ethDollars - idealDollarsOfEth) / blockSize;
            _tokenToSell = token2;
        }

        if (btcDollars > idealDollarsOfBtc + rebalanceDelta) {
            imbalanced = true;
            numBlocks = (btcDollars - idealDollarsOfBtc) / blockSize;
            _tokenToSell = token1;
        }
    }

    function rebalanceBuy() external {
        require(isRebalancing, "NOT REBALANCING");
        numBlocksLeftToSell -= 1;

        ERC20 sellToken = tokenToSell;
        ERC20 buyToken = sellToken == token1 ? token2 : token1;

        uint256 sellTokenAmount = _tokensFromDollars(sellToken, blockSize);
        uint256 buyTokenAmount = _tokensFromDollars(buyToken, blockSize);

        buyToken.transferFrom(_msgSender(), address(this), buyTokenAmount);
        sellToken.transfer(_msgSender(), sellTokenAmount);

        _endAuction();
    }

    function endAuction() external {
        _endAuction();
    }

    function _endAuction() internal {
        (bool needRebalance, , ) = _isImbalanced();
        if (!needRebalance) {
            isRebalancing = false;
            numBlocksLeftToSell = 0;
        }
    }
}
