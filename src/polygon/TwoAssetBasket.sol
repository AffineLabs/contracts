// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { Dollar, DollarMath } from "../DollarMath.sol";
import { DetailedShare } from "./Detailed.sol";

contract TwoAssetBasket is ERC20, BaseRelayRecipient, DetailedShare, Pausable {
    using SafeTransferLib for ERC20;
    address public governance;
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only Governance.");
        _;
    }

    // The token which we take in to buy token1 and token2, e.g. USDC
    // NOTE: Assuming that asset is $1 for now
    // TODO: allow component tokens to be bought using any token that has a USD price oracle
    ERC20 public asset;
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
    ) ERC20("Alpine Large Vault Token", "alpLarge", _tokens[0].decimals()) {
        require(_rebalanceDelta >= _blockSize, "DELTA_TOO_SMALL");
        governance = _governance;
        _setTrustedForwarder(forwarder);
        rebalanceDelta = _rebalanceDelta;
        blockSize = _blockSize;
        (token1, token2) = (_tokens[0], _tokens[1]);
        asset = _input;
        ratios = _ratios;
        uniRouter = _uniRouter;
        (priceFeed1, priceFeed2) = (_priceFeeds[0], _priceFeeds[1]);

        // Allow uniRouter to spend all tokens that we may swap
        asset.safeApprove(address(uniRouter), type(uint256).max);
        token1.safeApprove(address(uniRouter), type(uint256).max);
        token2.safeApprove(address(uniRouter), type(uint256).max);
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }

    function _msgSender() internal view override(Context, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }

    function _msgData() internal view override(Context, BaseRelayRecipient) returns (bytes calldata) {
        return BaseRelayRecipient._msgData();
    }

    function togglePause() external onlyGovernance {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /** DEPOSIT / WITHDRAW
     **************************************************************************/
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function deposit(uint256 amountInput, address receiver) external whenNotPaused returns (uint256 shares) {
        // Get current amounts of btc/eth (in dollars) => 8 decimals
        Dollar rawVaultDollars = valueOfVault();
        uint256 vaultDollars = Dollar.unwrap(rawVaultDollars);

        // We do two swaps. The amount of dollars we swap to each coin is determined by the ratios given above
        // See the whitepaper for the derivation of these amounts
        // Get dollar amounts of btc and eth to buy
        (uint256 amountInputToBtc, uint256 amountInputToEth) = _getBuySplits(amountInput);

        asset.transferFrom(_msgSender(), address(this), amountInput);
        address[] memory pathBtc = new address[](2);
        pathBtc[0] = address(asset);
        pathBtc[1] = address(token1);

        address[] memory pathEth = new address[](2);
        pathEth[0] = address(asset);
        pathEth[1] = address(token2);

        uint256 btcReceived;
        if (amountInputToBtc > 0) {
            uint256[] memory btcAmounts = uniRouter.swapExactTokensForTokens(
                amountInputToBtc,
                0,
                pathBtc,
                address(this),
                block.timestamp
            );
            btcReceived = btcAmounts[1];
        }

        uint256 ethReceived;
        if (amountInputToEth > 0) {
            uint256[] memory ethAmounts = uniRouter.swapExactTokensForTokens(
                amountInputToEth,
                0,
                pathEth,
                address(this),
                block.timestamp
            );
            ethReceived = ethAmounts[1];
        }

        Dollar rawDollarsReceived = _valueOfToken(token1, btcReceived).add(_valueOfToken(token2, ethReceived));
        uint256 dollarsReceived = Dollar.unwrap(rawDollarsReceived);

        // Issue shares based on dollar amounts of user coins vs total holdings of the vault
        if (totalSupply == 0) {
            // Dollars have 8 decimals, add an an extra 10 here to match the 18 that this contract uses
            shares = dollarsReceived * 1e10;
        } else {
            shares = (dollarsReceived * totalSupply) / vaultDollars;
        }

        emit Deposit(_msgSender(), receiver, amountInput, shares);
        _mint(receiver, shares);
    }

    event Withdraw(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    function withdraw(
        uint256 amountInput,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256 inputReceived) {
        // Try to get `amountInput` of `asset` out of vault
        Dollar rawVaultDollars = valueOfVault();
        uint256 vaultDollars = Dollar.unwrap(rawVaultDollars);

        // Get dollar amounts of btc and eth to sell
        (uint256 amountInputFromBtc, uint256 amountInputFromEth) = _getSellSplits(amountInput);

        // Get desired amount of asset from eth and btc reserves
        address[] memory pathBtc = new address[](2);
        pathBtc[0] = address(token1);
        pathBtc[1] = address(asset);

        address[] memory pathEth = new address[](2);
        pathEth[0] = address(token2);
        pathEth[1] = address(asset);

        if (amountInputFromBtc > 0) {
            uint256[] memory btcAmounts = uniRouter.swapExactTokensForTokens(
                // input token => dollars => btc conversion
                _tokensFromDollars(token1, _valueOfToken(asset, amountInputFromBtc)),
                0,
                pathBtc,
                address(this),
                block.timestamp
            );
            inputReceived += btcAmounts[1];
        }

        if (amountInputFromEth > 0) {
            uint256[] memory ethAmounts = uniRouter.swapExactTokensForTokens(
                // input token => dollars => eth conversion
                _tokensFromDollars(token2, _valueOfToken(asset, amountInputFromEth)),
                0,
                pathEth,
                address(this),
                block.timestamp
            );
            inputReceived += ethAmounts[1];
        }

        // NOTE: The user eats the slippage and trading fees. E.g. if you request $10 you may only get $9 out

        // Calculate number of shares to burn with numShares = dollarAmount * shares_per_dollar
        // Try to burn numShares, will revert if user does not have enough

        // NOTE: Even if inputReceived > amountInput, the vault only sold $amountInputDollars worth of assets
        // (according to chainlink). The share price is a chainlink price, and so the user can at most be asked to
        // burn $amountInputDollars worth of shares

        // Convert from Dollar for easy calculations
        uint256 amountInputDollars = Dollar.unwrap(_valueOfToken(asset, amountInput));
        uint256 numShares = (amountInputDollars * totalSupply) / vaultDollars;

        // TODO: fix approvals, anyone can burn a user's shares now
        _burn(owner, numShares);

        emit Withdraw(_msgSender(), receiver, owner, amountInput, numShares);
        asset.transfer(receiver, inputReceived);
    }

    /** EXCHANGE RATES
     **************************************************************************/

    // Dollars always have 8 decimals
    using DollarMath for Dollar;

    function _getTokenPrice(ERC20 token) internal view returns (Dollar) {
        // NOTE: Chainlink price feeds report prices of the "base unit" of your token. So
        // we receive the price of 1 ether (1e18 wei). The price also comes with its own decimals. E.g. a price
        // of $1 with 8 decimals is given as 1e8.

        if (token == asset) {
            return Dollar.wrap(uint256(1e8));
        }

        AggregatorV3Interface feed;
        if (token == token1) {
            feed = priceFeed1;
        } else {
            feed = priceFeed2;
        }
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = feed.latestRoundData();
        require(price > 0, "Chainlink price <= 0");
        require(answeredInRound >= roundId, "Chainlink stale data");
        require(timestamp != 0, "Chainlink round not complete");
        return Dollar.wrap(uint256(price));
    }

    function _valueOfToken(ERC20 token, uint256 amount) public view returns (Dollar) {
        // Convert tokens to dollars using as many decimal places as the price feed gives us
        // e.g. Say ether is $1. If the price feed uses 8 decimals then a price of $1 is 1e8.
        // If we have 2 ether then return 2 * 1e8 as the dollar value of our balance

        uint256 tokenPrice = Dollar.unwrap(_getTokenPrice(token));
        uint256 dollarValue = (amount * tokenPrice) / (10**token.decimals());
        return Dollar.wrap(dollarValue);
    }

    function valueOfVault() public view returns (Dollar) {
        (Dollar btcDollars, Dollar ethDollars) = _valueOfVaultComponents();
        return btcDollars.add(ethDollars);
    }

    function _valueOfVaultComponents() internal view returns (Dollar, Dollar) {
        uint256 btcBal = token1.balanceOf(address(this));
        uint256 ethBal = token2.balanceOf(address(this));

        Dollar btcDollars = _valueOfToken(token1, btcBal);
        Dollar ethDollars = _valueOfToken(token2, ethBal);
        return (btcDollars, ethDollars);
    }

    /// @notice   When depositing, determine amount of input token that should be used to buy BTC and ETH respectively
    function _getBuySplits(uint256 amountInput) internal view returns (uint256 btcAmount, uint256 ethAmount) {
        Dollar rawInputDollars = _valueOfToken(asset, amountInput);
        uint256 inputDollars = Dollar.unwrap(rawInputDollars);

        // We don't care about decimals here, so we can simply treat these as integers
        (Dollar rawBtcDollars, Dollar rawEthDollars) = _valueOfVaultComponents();
        uint256 btcDollars = Dollar.unwrap(rawBtcDollars);
        uint256 ethDollars = Dollar.unwrap(rawEthDollars);

        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);

        // (a - b) represents the amount of dollars we want to swap for btc
        uint256 a = (r1 * (ethDollars + inputDollars)) / (r1 + r2);
        uint256 b = (r2 * btcDollars) / (r1 + r2);

        // Case 1: We want to buy a negative amount of btc. Just spend all of input token on eth.
        if (b > a) {
            btcAmount = 0;
            ethAmount = amountInput;
        } else if (a - b > inputDollars) {
            // Case 2:
            // We want to buy btc with more of asset than we have. Cap the dollars going to btc
            btcAmount = amountInput;
            ethAmount = 0;
        } else {
            // Case 3:
            // The regular case where we split the input. Some amount of money goes to btc, the rest goes to eth
            uint256 dollarsToBtc = a - b;
            btcAmount = (dollarsToBtc * amountInput) / inputDollars;
            ethAmount = amountInput - btcAmount;
        }
    }

    function _getSellSplits(uint256 amountInput) internal view returns (uint256 btcAmount, uint256 ethAmount) {
        Dollar rawInputDollars = _valueOfToken(asset, amountInput);
        uint256 inputDollars = Dollar.unwrap(rawInputDollars);

        // We don't care about decimals here, so we can simply treat these as integers
        (Dollar rawBtcDollars, Dollar rawEthDollars) = _valueOfVaultComponents();
        uint256 btcDollars = Dollar.unwrap(rawBtcDollars);
        uint256 ethDollars = Dollar.unwrap(rawEthDollars);

        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);

        // Using signed integers because ethDollars - inputDollars could underflow
        int256 a = int256((r2 * btcDollars) / (r1 + r2));
        int256 b = (int256(r1) * (int256(ethDollars) - int256(inputDollars))) / int256(r1 + r2);

        // (a - b) represents the amount of dollars in btc we want to sell (see whitepaper)
        int256 amountBtcToSell = a - b;
        // Case 1: We don't want to sell any btc
        if (amountBtcToSell < 0) {
            btcAmount = 0;
            ethAmount = amountInput;
        } else if (uint256(amountBtcToSell) > inputDollars) {
            // Case 2: We want to sell only btc
            // Cap the amount that we attempt to liquidate from btc
            btcAmount = amountInput;
            ethAmount = 0;
        } else {
            //  Case 3: The regular case where we split the input. Some amount of money comes from btc,
            // the rest goes comes from eth
            btcAmount = (uint256(amountBtcToSell) * amountInput) / inputDollars;
            ethAmount = amountInput - btcAmount;
        }
    }

    function _tokensFromDollars(ERC20 token, Dollar amountDollars) internal view returns (uint256) {
        // Convert dollars to tokens with token's amount of decimals
        uint256 oneToken = 10**token.decimals();

        uint256 amountDollarsInt = Dollar.unwrap(amountDollars);
        uint256 tokenPrice = Dollar.unwrap(_getTokenPrice(token));
        return (amountDollarsInt * oneToken) / tokenPrice;
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
        (Dollar rawBtcDollars, Dollar rawEthDollars) = _valueOfVaultComponents();
        uint256 btcDollars = Dollar.unwrap(rawBtcDollars);
        uint256 ethDollars = Dollar.unwrap(rawEthDollars);

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

        uint256 sellTokenAmount = _tokensFromDollars(sellToken, Dollar.wrap(blockSize));
        uint256 buyTokenAmount = _tokensFromDollars(buyToken, Dollar.wrap(blockSize));

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

    /** DETAILED PRICE INFO
     **************************************************************************/

    function detailedTVL() external view override returns (Number memory tvl) {
        Dollar vaultDollars = valueOfVault();
        tvl = Number({ num: Dollar.unwrap(vaultDollars), decimals: 8 });
    }

    function detailedPrice() external view override returns (Number memory price) {
        Dollar vaultDollars = valueOfVault();
        uint256 vaultValue = Dollar.unwrap(vaultDollars);
        uint256 _price;
        uint256 shareDecimals = decimals;

        // Assuming that shareDecimals > 8. TODO: reconsider
        _price = (vaultValue * (10**shareDecimals)) / totalSupply;

        price = Number({ num: _price, decimals: 8 });
    }

    function detailedTotalSupply() external view override returns (Number memory supply) {
        supply = Number({ num: totalSupply, decimals: decimals });
    }
}
