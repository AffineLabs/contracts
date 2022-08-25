// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";

import { AffineGovernable } from "../AffineGovernable.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { Dollar, DollarMath } from "../DollarMath.sol";
import { DetailedShare } from "./Detailed.sol";

contract TwoAssetBasket is ERC20, BaseRelayRecipient, DetailedShare, Pausable, AffineGovernable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // The token which we take in to buy token1 and token2, e.g. USDC
    ERC20 public asset;
    ERC20 public token1;
    ERC20 public token2;

    uint256[2] public ratios;

    IUniLikeSwapRouter public uniRouter;

    // These must be USD price feeds for token1 and token2
    mapping(ERC20 => AggregatorV3Interface) public tokenToOracle;

    constructor(
        address _governance,
        address forwarder,
        IUniLikeSwapRouter _uniRouter,
        ERC20 _input,
        ERC20[2] memory _tokens,
        uint256[2] memory _ratios,
        AggregatorV3Interface[3] memory _priceFeeds
    ) ERC20("Alpine Large Vault Token", "alpLarge", _tokens[0].decimals()) {
        governance = _governance;
        _setTrustedForwarder(forwarder);
        (token1, token2) = (_tokens[0], _tokens[1]);
        asset = _input;
        ratios = _ratios;
        uniRouter = _uniRouter;

        tokenToOracle[asset] = _priceFeeds[0];
        tokenToOracle[token1] = _priceFeeds[1];
        tokenToOracle[token2] = _priceFeeds[2];

        // Allow uniRouter to spend all tokens that we may swap
        asset.safeApprove(address(uniRouter), type(uint256).max);
        token1.safeApprove(address(uniRouter), type(uint256).max);
        token2.safeApprove(address(uniRouter), type(uint256).max);

        assetLimit = 10_000 * 1e8;
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

    /**
     * @notice Set the trusted forwarder address
     * @param forwarder The new forwarder address
     */
    function setTrustedForwarder(address forwarder) external onlyGovernance {
        _setTrustedForwarder(forwarder);
    }

    /// @notice Pause the contract
    function pause() external onlyGovernance {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyGovernance {
        _unpause();
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
        uint256 vaultDollars = Dollar.unwrap(valueOfVault());

        // TODO: remove after mainnet alpha
        {
            uint256 tvl = vaultDollars;
            uint256 allowedDepositAmount = tvl > assetLimit ? 0 : assetLimit - tvl;
            uint256 allowedDollars = Math.min(allowedDepositAmount, Dollar.unwrap(_valueOfToken(asset, amountInput)));
            amountInput = _tokensFromDollars(asset, Dollar.wrap(allowedDollars));
        }
        // end TODO

        // We do two swaps. The amount of dollars we swap to each coin is determined by the ratios given above
        // See the whitepaper for the derivation of these amounts
        // Get  of btc and eth to buy (in `asset`)
        (uint256 amountInputToBtc, uint256 amountInputToEth) = _getBuySplits(amountInput);

        asset.safeTransferFrom(_msgSender(), address(this), amountInput);
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

        uint256 dollarsReceived = Dollar.unwrap(
            _valueOfToken(token1, btcReceived).add(_valueOfToken(token2, ethReceived))
        );

        // Issue shares based on dollar amounts of user coins vs total holdings of the vault
        if (totalSupply == 0) {
            // Dollars have 8 decimals, add an an extra 10 here to match the 18 that this contract uses
            shares = ((dollarsReceived * 1e10) / 100);
        } else {
            shares = (dollarsReceived * totalSupply) / vaultDollars;
        }

        emit Deposit(_msgSender(), receiver, amountInput, shares);
        _mint(receiver, shares);
    }

    function withdraw(
        uint256 amountInput,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256 inputReceived) {
        // Try to get `amountInput` of `asset` out of vault
        uint256 vaultDollars = Dollar.unwrap(valueOfVault());

        // Get dollar amounts of btc and eth to sell
        (Dollar dollarsFromBtc, Dollar dollarsFromEth) = _getSellSplits(amountInput);

        address[] memory pathBtc = new address[](2);
        pathBtc[0] = address(token1);
        pathBtc[1] = address(asset);

        address[] memory pathEth = new address[](2);
        pathEth[0] = address(token2);
        pathEth[1] = address(asset);

        if (Dollar.unwrap(dollarsFromBtc) > 0) {
            uint256[] memory btcAmounts = uniRouter.swapExactTokensForTokens(
                // input token => dollars => btc conversion
                _tokensFromDollars(token1, dollarsFromBtc),
                0,
                pathBtc,
                address(this),
                block.timestamp
            );
            inputReceived += btcAmounts[1];
        }

        if (Dollar.unwrap(dollarsFromEth) > 0) {
            uint256[] memory ethAmounts = uniRouter.swapExactTokensForTokens(
                // input token => dollars => eth conversion
                _tokensFromDollars(token2, dollarsFromEth),
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
        asset.safeTransfer(receiver, inputReceived);
    }

    /** EXCHANGE RATES
     **************************************************************************/

    // Dollars always have 8 decimals
    using DollarMath for Dollar;

    function _getTokenPrice(ERC20 token) internal view returns (Dollar) {
        // NOTE: Chainlink price feeds report prices of the "base unit" of your token. So
        // we receive the price of 1 ether (1e18 wei). The price also comes with its own decimals. E.g. a price
        // of $1 with 8 decimals is given as 1e8.

        AggregatorV3Interface feed = tokenToOracle[token];

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

    function _valueOfVaultComponents() public view returns (Dollar, Dollar) {
        uint256 btcBal = token1.balanceOf(address(this));
        uint256 ethBal = token2.balanceOf(address(this));

        Dollar btcDollars = _valueOfToken(token1, btcBal);
        Dollar ethDollars = _valueOfToken(token2, ethBal);
        return (btcDollars, ethDollars);
    }

    function _tokensFromDollars(ERC20 token, Dollar amountDollars) internal view returns (uint256) {
        // Convert dollars to tokens with token's amount of decimals
        uint256 oneToken = 10**token.decimals();

        uint256 amountDollarsInt = Dollar.unwrap(amountDollars);
        uint256 tokenPrice = Dollar.unwrap(_getTokenPrice(token));
        return (amountDollarsInt * oneToken) / tokenPrice;
    }

    /// @notice   When depositing, determine amount of input token that should be used to buy BTC and ETH respectively
    function _getBuySplits(uint256 amountInput) public view returns (uint256 assetToBtc, uint256 assetToEth) {
        uint256 inputDollars = Dollar.unwrap(_valueOfToken(asset, amountInput));

        // We don't care about decimals here, so we can simply treat these as integers
        (Dollar rawBtcDollars, Dollar rawEthDollars) = _valueOfVaultComponents();
        uint256 btcDollars = Dollar.unwrap(rawBtcDollars);
        uint256 ethDollars = Dollar.unwrap(rawEthDollars);
        uint256 vaultDollars = ethDollars + btcDollars;

        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);

        // Calculate idealAmount of Btc
        uint256 idealBtcDollars = (r1 * (vaultDollars)) / (r1 + r2);
        uint256 idealEthDollars = vaultDollars - idealBtcDollars;

        // In both steps we buy until we hit the ideal amount. Then we use the ratios
        uint256 dollarsToBtc;

        // 1. If Ideal amount is less than current amount then we buy btc (too little btc)
        if (btcDollars < idealBtcDollars) {
            uint256 amountNeeded = idealBtcDollars - btcDollars;
            if (amountNeeded > inputDollars) dollarsToBtc = inputDollars;
            else {
                // Hit ideal amount of btc
                dollarsToBtc += amountNeeded;
                // We've hit the ideal amount of btc, now buy according to the ratios
                uint256 remaining = inputDollars - amountNeeded;
                dollarsToBtc += (r1 * (remaining)) / (r1 + r2);
            }
        }
        // 2. If ideal amount is greater than current amount we buy eth (too little eth)
        else {
            uint256 amountNeeded = idealEthDollars - ethDollars;
            if (amountNeeded > inputDollars) {
                // dollarsToBtc will just remain 0
            } else {
                // We've hit the ideal amount of eth, now buy according to the ratios
                uint256 remaining = inputDollars - amountNeeded;
                dollarsToBtc = (r1 * (remaining)) / (r1 + r2);
            }
        }
        // Convert from dollars back to the input asset
        assetToBtc = _tokensFromDollars(asset, Dollar.wrap(dollarsToBtc));
        assetToEth = amountInput - assetToBtc;
    }

    /// @notice The same as getBuySplits, but with some signs reversed and we return dollar amounts
    function _getSellSplits(uint256 amountInput) public view returns (Dollar, Dollar) {
        uint256 inputDollars = Dollar.unwrap(_valueOfToken(asset, amountInput));

        // We don't care about decimals here, so we can simply treat these as integers
        (Dollar rawBtcDollars, Dollar rawEthDollars) = _valueOfVaultComponents();
        uint256 btcDollars = Dollar.unwrap(rawBtcDollars);
        uint256 ethDollars = Dollar.unwrap(rawEthDollars);
        uint256 vaultDollars = ethDollars + btcDollars;

        (uint256 r1, uint256 r2) = (ratios[0], ratios[1]);

        // Calculate idealAmount of Btc
        uint256 idealBtcDollars = (r1 * (vaultDollars)) / (r1 + r2);
        uint256 idealEthDollars = vaultDollars - idealBtcDollars;

        // In both steps we sell until we hit the ideal amount. Then we use the ratios.
        uint256 dollarsFromBtc;

        // 1. If ideal amount is greater than current amount we sell btc (too much btc)
        if (idealBtcDollars < btcDollars) {
            uint256 amountNeeded = btcDollars - idealBtcDollars;
            if (amountNeeded > inputDollars) dollarsFromBtc = inputDollars;
            else {
                // Hit ideal amount of btc
                dollarsFromBtc += amountNeeded;
                // We've hit the ideal amount of btc, now sell according to the ratios
                uint256 remaining = inputDollars - amountNeeded;
                dollarsFromBtc += (r1 * (remaining)) / (r1 + r2);
            }
        }
        // 2. If ideal amount is less than current amount we sell Eth (too little btc)
        else {
            uint256 amountNeeded = ethDollars - idealEthDollars;
            if (amountNeeded > inputDollars) {
                // dollarsFromBtc will remain 0
            } else {
                // We've hit the ideal amount of eth, now sell according to the ratios
                uint256 remaining = inputDollars - amountNeeded;
                dollarsFromBtc = (r1 * (remaining)) / (r1 + r2);
            }
        }

        return (Dollar.wrap(dollarsFromBtc), Dollar.wrap(inputDollars - dollarsFromBtc));
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
        // Price is set to 1 if there are no shares in the vault
        if (totalSupply > 0) {
            _price = (vaultValue * (10**shareDecimals)) / totalSupply;
        } else {
            _price = 10**8;
        }

        price = Number({ num: _price, decimals: 8 });
    }

    function detailedTotalSupply() external view override returns (Number memory supply) {
        supply = Number({ num: totalSupply, decimals: decimals });
    }

    /** MAINNET ALPHA TEMP STUFF
     **************************************************************************/
    /// @notice This is actually a dollar amount We don't bother with `Dollar` type because this is external
    uint256 assetLimit;

    function setAssetLimit(uint256 _assetLimit) external onlyGovernance {
        assetLimit = _assetLimit;
    }

    /// @dev This function must be submitted through a private RPC. We liquidate all assets and then
    ///  pause deposits and withdrawals
    function prepareForTeardown() external onlyGovernance {
        // Pause deposits/withdrawals
        _pause();

        // Liquidate all assets
        address[] memory pathBtc = new address[](2);
        pathBtc[0] = address(token1);
        pathBtc[1] = address(asset);

        address[] memory pathEth = new address[](2);
        pathEth[0] = address(token2);
        pathEth[1] = address(asset);

        uniRouter.swapExactTokensForTokens(token1.balanceOf(address(this)), 0, pathBtc, address(this), block.timestamp);
        uniRouter.swapExactTokensForTokens(token2.balanceOf(address(this)), 0, pathEth, address(this), block.timestamp);
    }

    /// @dev This should only be called after prepareForTeardown is called. Can be called as many times as needed
    function tearDown(address[] calldata users) external onlyGovernance {
        uint256 totalAssets = asset.balanceOf(address(this));
        uint256 numShares = totalSupply;
        uint256 length = users.length;
        for (uint256 i = 0; i < length; ) {
            address user = users[i];
            uint256 shares = balanceOf[user];

            uint256 assets = shares.mulDivDown(totalAssets, numShares);

            _burn(user, shares);
            asset.safeTransfer(user, assets);
            unchecked {
                ++i;
            }
        }
    }
}
