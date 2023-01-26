// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {BaseRelayRecipient} from "@opengsn/contracts/src/BaseRelayRecipient.sol";

import {AffineGovernable} from "../AffineGovernable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {Dollar, DollarMath} from "../libs/DollarMath.sol";
import {DetailedShare} from "../both/Detailed.sol";

contract TwoAssetBasket is
    ERC20Upgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    BaseRelayRecipient,
    DetailedShare,
    AffineGovernable
{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                          ASSET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The asset which we take in to buy btc and weth, e.g. USDC
    ERC20 public asset;
    /// @notice The wrapped bitcoin address.
    ERC20 public btc;
    /// @notice The wrapped eth address
    ERC20 public weth;

    /// @notice [r1, r2] is the ratio of btcoin to ethereum
    uint256[2] public ratios;

    /// @notice The uniswap router.
    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    /// @notice USD price feeds for btc and weth
    mapping(ERC20 => AggregatorV3Interface) public tokenToOracle;

    function initialize(
        address _governance,
        address forwarder,
        ERC20 _asset,
        ERC20[2] memory _tokens,
        uint256[2] memory _ratios,
        AggregatorV3Interface[3] memory _priceFeeds
    ) public initializer {
        __ERC20_init("Large Cap", "largeCap");
        __UUPSUpgradeable_init();
        __Pausable_init();

        governance = _governance;
        _setTrustedForwarder(forwarder);
        (btc, weth) = (_tokens[0], _tokens[1]);
        asset = _asset;
        ratios = _ratios;

        tokenToOracle[asset] = _priceFeeds[0];
        tokenToOracle[btc] = _priceFeeds[1];
        tokenToOracle[weth] = _priceFeeds[2];

        // Allow ROUTER to spend all tokens that we may swap
        asset.safeApprove(address(ROUTER), type(uint256).max);
        btc.safeApprove(address(ROUTER), type(uint256).max);
        weth.safeApprove(address(ROUTER), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                           META-TRANSACTIONS
    //////////////////////////////////////////////////////////////*/

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }

    function _msgSender() internal view override(ContextUpgradeable, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, BaseRelayRecipient) returns (bytes calldata) {
        return BaseRelayRecipient._msgData();
    }

    /**
     * @notice Set the trusted forwarder address
     * @param forwarder The new forwarder address
     */
    function setTrustedForwarder(address forwarder) external onlyGovernance {
        _setTrustedForwarder(forwarder);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @notice Pause the contract.
    function pause() external onlyGovernance {
        _pause();
    }

    /// @notice Unpause the contract.
    function unpause() external onlyGovernance {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @notice 4626 style deposits
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @notice 4626 style deposits with slippage protection.
    function deposit(uint256 assets, address receiver, uint256 minSharesOut) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
        require(shares > minSharesOut, "TAB: min shares");
    }

    /// @dev deposit helper. Converts `asset` into apporiate amount of
    function _deposit(uint256 assets, address receiver) internal whenNotPaused returns (uint256 shares) {
        // Get current amounts of btc/eth (in dollars) => 8 decimals
        uint256 vaultDollars = Dollar.unwrap(valueOfVault());

        // We do two swaps. The amount of dollars we swap to each coin is determined by the ratios given above
        // Get amounts of btc and eth to buy (in `asset`)
        (uint256 assetsToBtc, uint256 assetsToEth) = _getBuySplits(assets);

        asset.safeTransferFrom(_msgSender(), address(this), assets);
        uint256 btcReceived;
        if (assetsToBtc > 0) {
            uint256[] memory btcAmounts = ROUTER.swapExactTokensForTokens({
                amountIn: assetsToBtc,
                amountOutMin: 0,
                path: _pathBtc(true),
                to: address(this),
                deadline: block.timestamp
            });
            btcReceived = btcAmounts[btcAmounts.length - 1];
        }

        uint256 ethReceived;
        if (assetsToEth > 0) {
            uint256[] memory ethAmounts = ROUTER.swapExactTokensForTokens({
                amountIn: assetsToEth,
                amountOutMin: 0,
                path: _pathEth(true),
                to: address(this),
                deadline: block.timestamp
            });
            ethReceived = ethAmounts[ethAmounts.length - 1];
        }

        uint256 dollarsReceived = Dollar.unwrap(_valueOfToken(btc, btcReceived).add(_valueOfToken(weth, ethReceived)));

        // Issue shares based on dollar amounts of user coins vs total holdings of the vault
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            // Dollars have 8 decimals, add an an extra 10 here to match the 18 that this contract uses
            shares = ((dollarsReceived * 1e10) / 100);
        } else {
            shares = (dollarsReceived * _totalSupply) / vaultDollars;
        }

        emit Deposit(_msgSender(), receiver, assets, shares);
        _mint(receiver, shares);
    }
    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice 4626 style withdrawals.
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxSharesBurned)
        external
        returns (uint256 shares)
    {
        shares = _withdraw(assets, receiver, owner);
        require(shares < maxSharesBurned, "TAB: max shares");
    }

    /// @notice 4626 style withdrawals with slippage protection.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner);
    }

    /// @notice Withdraw helper.
    function _withdraw(uint256 assets, address receiver, address owner)
        internal
        whenNotPaused
        returns (uint256 shares)
    {
        // Try to get `assets` of `asset` out of vault
        uint256 vaultDollars = Dollar.unwrap(valueOfVault());

        // Get dollar amounts of btc and eth to sell
        (Dollar dollarsFromBtc, Dollar dollarsFromEth) = _getSellSplits(assets);

        uint256 assetsReceived = _sell(dollarsFromBtc, dollarsFromEth);

        // NOTE: Even if assetsReceived > assets, the vault only sold $assetsDollars worth of assets
        // (according to chainlink). The share price is a chainlink price, and so the user can at most be asked to
        // burn $assetsDollars worth of shares

        // Convert from Dollar for easy calculations
        uint256 assetsDollars = Dollar.unwrap(_valueOfToken(asset, assets));
        shares = (assetsDollars * totalSupply()) / vaultDollars;

        // Try to burn shares, will revert if user does not have enough
        address caller = _msgSender();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        emit Withdraw(_msgSender(), receiver, owner, assetsReceived, shares);
        asset.safeTransfer(receiver, assetsReceived);
    }

    /// @notice 4626 style redemptions with slippage protection.
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssetsOut)
        external
        returns (uint256 assets)
    {
        assets = _redeem(shares, receiver, owner);
        require(assets > minAssetsOut, "TAB: min assets");
    }

    /// @notice 4626 style redemptions.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner);
    }

    /// @dev Redemption helper.
    function _redeem(uint256 shares, address receiver, address owner) internal whenNotPaused returns (uint256 assets) {
        // Convert shares to dollar amounts

        // Try to get `assets` of `asset` out of vault
        uint256 vaultDollars = Dollar.unwrap(valueOfVault());
        uint256 dollars = shares.mulDivDown(vaultDollars, totalSupply());
        uint256 assetsToSell = _tokensFromDollars(asset, Dollar.wrap(dollars));

        // Get dollar amounts of btc and eth to sell
        (Dollar dollarsFromBtc, Dollar dollarsFromEth) = _getSellSplits(assetsToSell);
        assets = _sell(dollarsFromBtc, dollarsFromEth);

        address caller = _msgSender();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
        asset.safeTransfer(receiver, assets);
    }

    /// @dev Sell wbtc/weth.
    function _sell(Dollar dollarsFromBtc, Dollar dollarsFromEth) internal returns (uint256 assetsReceived) {
        if (Dollar.unwrap(dollarsFromBtc) > 0) {
            uint256[] memory btcAmounts = ROUTER.swapExactTokensForTokens({
                // asset => dollars => btc conversion
                amountIn: Math.min(_tokensFromDollars(btc, dollarsFromBtc), btc.balanceOf(address(this))),
                amountOutMin: 0,
                path: _pathBtc(false),
                to: address(this),
                deadline: block.timestamp
            });
            assetsReceived += btcAmounts[btcAmounts.length - 1];
        }

        if (Dollar.unwrap(dollarsFromEth) > 0) {
            uint256[] memory ethAmounts = ROUTER.swapExactTokensForTokens({
                amountIn: Math.min(_tokensFromDollars(weth, dollarsFromEth), weth.balanceOf(address(this))),
                amountOutMin: 0,
                path: _pathEth(false),
                to: address(this),
                deadline: block.timestamp
            });
            assetsReceived += ethAmounts[ethAmounts.length - 1];
        }
    }

    /*//////////////////////////////////////////////////////////////
                             EXCHANGE RATES
    //////////////////////////////////////////////////////////////*/

    // Dollars always have 8 decimals
    using DollarMath for Dollar;

    /// @dev Get chainlink price of usdc, wbtc, weth.
    function _getTokenPrice(ERC20 token) internal view returns (Dollar) {
        // NOTE: Chainlink price feeds report prices of the "base unit" of your token. So
        // we receive the price of 1 ether (1e18 wei). The price also comes with its own decimals. E.g. a price
        // of $1 with 8 decimals is given as 1e8.

        AggregatorV3Interface feed = tokenToOracle[token];

        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = feed.latestRoundData();
        require(price > 0, "TAB: price <= 0");
        require(answeredInRound >= roundId, "TAB: stale data");
        require(timestamp != 0, "TAB: round not done");
        return Dollar.wrap(uint256(price));
    }

    /// @notice Total dollar value of vault.
    function valueOfVault() public view returns (Dollar) {
        (Dollar btcDollars, Dollar ethDollars) = _valueOfVaultComponents();
        return btcDollars.add(ethDollars);
    }

    /// @dev Convert a token amount into a dollar amount.
    function _valueOfToken(ERC20 token, uint256 amount) public view returns (Dollar) {
        // Convert tokens to dollars using as many decimal places as the price feed gives us
        // e.g. Say ether is $1. If the price feed uses 8 decimals then a price of $1 is 1e8.
        // If we have 2 ether then return 2 * 1e8 as the dollar value of our balance
        uint256 tokenPrice = Dollar.unwrap(_getTokenPrice(token));
        uint256 dollarValue = (amount * tokenPrice) / (10 ** token.decimals());
        return Dollar.wrap(dollarValue);
    }

    /// @dev Dollar value held in each component asset (i.e. wbtc and weth).
    function _valueOfVaultComponents() public view returns (Dollar, Dollar) {
        uint256 btcBal = btc.balanceOf(address(this));
        uint256 ethBal = weth.balanceOf(address(this));

        Dollar btcDollars = _valueOfToken(btc, btcBal);
        Dollar ethDollars = _valueOfToken(weth, ethBal);
        return (btcDollars, ethDollars);
    }

    /// @dev Convert dollar amounts to token amounts.
    function _tokensFromDollars(ERC20 token, Dollar amountDollars) internal view returns (uint256) {
        // Convert dollars to tokens with token's amount of decimals
        uint256 oneToken = 10 ** token.decimals();

        uint256 amountDollarsInt = Dollar.unwrap(amountDollars);
        uint256 tokenPrice = Dollar.unwrap(_getTokenPrice(token));
        return (amountDollarsInt * oneToken) / tokenPrice;
    }

    /// @notice  When depositing, determine amount of asset token that should be used to buy BTC and ETH respectively/
    function _getBuySplits(uint256 assets) public view returns (uint256 assetToBtc, uint256 assetToEth) {
        uint256 assetDollars = Dollar.unwrap(_valueOfToken(asset, assets));

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
            if (amountNeeded > assetDollars) {
                dollarsToBtc = assetDollars;
            } else {
                // Hit ideal amount of btc
                dollarsToBtc += amountNeeded;
                // We've hit the ideal amount of btc, now buy according to the ratios
                uint256 remaining = assetDollars - amountNeeded;
                dollarsToBtc += (r1 * (remaining)) / (r1 + r2);
            }
        }
        // 2. If ideal amount is greater than current amount we buy eth (too little eth)
        else {
            uint256 amountNeeded = idealEthDollars - ethDollars;
            if (amountNeeded > assetDollars) {
                // dollarsToBtc will just remain 0
            } else {
                // We've hit the ideal amount of eth, now buy according to the ratios
                uint256 remaining = assetDollars - amountNeeded;
                dollarsToBtc = (r1 * (remaining)) / (r1 + r2);
            }
        }
        // Convert from dollars back to the asset asset
        assetToBtc = _tokensFromDollars(asset, Dollar.wrap(dollarsToBtc));
        assetToEth = assets - assetToBtc;
    }

    /// @notice The same as getBuySplits, but with some signs reversed and we return dollar amounts
    function _getSellSplits(uint256 assets) public view returns (Dollar, Dollar) {
        uint256 assetDollars = Dollar.unwrap(_valueOfToken(asset, assets));

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
            if (amountNeeded > assetDollars) {
                dollarsFromBtc = assetDollars;
            } else {
                // Hit ideal amount of btc
                dollarsFromBtc += amountNeeded;
                // We've hit the ideal amount of btc, now sell according to the ratios
                uint256 remaining = assetDollars - amountNeeded;
                dollarsFromBtc += (r1 * (remaining)) / (r1 + r2);
            }
        }
        // 2. If ideal amount is less than current amount we sell Eth (too little btc)
        else {
            uint256 amountNeeded = ethDollars - idealEthDollars;
            if (amountNeeded > assetDollars) {
                // dollarsFromBtc will remain 0
            } else {
                // We've hit the ideal amount of eth, now sell according to the ratios
                uint256 remaining = assetDollars - amountNeeded;
                dollarsFromBtc = (r1 * (remaining)) / (r1 + r2);
            }
        }

        return (Dollar.wrap(dollarsFromBtc), Dollar.wrap(assetDollars - dollarsFromBtc));
    }

    /// @dev Paths used when buying/selling weth.
    function _pathEth(bool buy) internal view returns (address[] memory path) {
        path = new address[](2);
        if (buy) {
            path[0] = address(asset);
            path[1] = address(weth);
        } else {
            path[0] = address(weth);
            path[1] = address(asset);
        }
    }

    /// @dev Paths used when buying/selling wbtc.
    function _pathBtc(bool buy) internal view returns (address[] memory path) {
        path = new address[](3);
        if (buy) {
            path[0] = address(asset);
            path[1] = address(weth);
            path[2] = address(btc);
        } else {
            path[0] = address(btc);
            path[1] = address(weth);
            path[2] = address(asset);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             DETAILED INFO
    //////////////////////////////////////////////////////////////*/
    function detailedTVL() external view override returns (Number memory tvl) {
        Dollar vaultDollars = valueOfVault();
        tvl = Number({num: Dollar.unwrap(vaultDollars), decimals: 8});
    }

    function detailedPrice() external view override returns (Number memory price) {
        Dollar vaultDollars = valueOfVault();
        uint256 vaultValue = Dollar.unwrap(vaultDollars);
        uint256 _price;
        uint256 shareDecimals = decimals();

        uint256 _totalSupply = totalSupply();

        // Price is set to 100 if there are no shares in the vault
        if (_totalSupply > 0) {
            _price = (vaultValue * (10 ** shareDecimals)) / _totalSupply;
        } else {
            _price = 100e8;
        }

        price = Number({num: _price, decimals: 8});
    }

    function detailedTotalSupply() external view override returns (Number memory supply) {
        supply = Number({num: totalSupply(), decimals: decimals()});
    }
}
