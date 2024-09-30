// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

/* solhint-disable */

// upgrading contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// safeTransfer
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

// storage
import {OmniUltraLRTStorage} from "./OmniUltraLRTStorage.sol";

// IPriceFeed
import {IPriceFeed} from "../price-feed/IPriceFeed.sol";
// withdrawal escrow
import {OmniWithdrawalEscrow} from "./OmniWithdrawalEscrow.sol";

import {UltraLRT} from "../UltraLRT.sol";

contract OmniUltraLRT is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    OmniUltraLRTStorage
{
    using SafeTransferLib for ERC20;
    using MathUpgradeable for uint256;
    // Constructor

    constructor() {
        // disable initializer
        _disableInitializers();
    }

    // Initialize
    function initialize(
        string memory name_,
        string memory symbol_,
        address _governance,
        address _harvester,
        address _manager,
        uint256 _performanceFeeBps,
        uint256 _managementFeeBps,
        uint256 _withdrawalFeeBps
    ) public initializer {
        // Initialize AccessControl
        __AccessControl_init();
        // Initialize Pausable
        __Pausable_init();
        // Initialize ERC20
        __ERC20_init(name_, symbol_);
        // Initialize ReentrancyGuard
        __ReentrancyGuard_init();

        // Set roles
        _setupRole(DEFAULT_ADMIN_ROLE, _governance);
        _setupRole(GOVERNANCE_ROLE, _governance);
        _setupRole(HARVESTER_ROLE, _governance);
        _setupRole(HARVESTER_ROLE, _harvester);
        _setupRole(MANAGER_ROLE, _governance);
        _setupRole(MANAGER_ROLE, _manager);

        // Set fees
        performanceFeeBps = _performanceFeeBps;
        managementFeeBps = _managementFeeBps;
        withdrawalFeeBps = _withdrawalFeeBps;
    }
    // Declare functions and modifiers here

    // only gov can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(GOVERNANCE_ROLE) {}

    // pause and unpause functions

    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    // add new asset to the vault
    function addAsset(address asset, address vault, address priceFeed) external onlyRole(GOVERNANCE_ROLE) {
        // add asset
        require(assetCount < 50, "MAX_ASSETS_REACHED");
        require(vaults[asset] == address(0), "ASSET_EXISTS");

        assets[assetCount] = asset;
        vaults[asset] = vault;
        wQueues[asset] = address(0); // todo set withdrawal queue
        priceFeeds[asset] = priceFeed;
        assetCount++;
    }

    // set price feed
    // set a new price feed in case of old one is not working
    function setPriceFeed(address asset, address priceFeed) external onlyRole(GOVERNANCE_ROLE) {
        // set price feed
        priceFeeds[asset] = priceFeed;
    }

    // todo implement
    function removeAsset(address asset) external onlyRole(GOVERNANCE_ROLE) {
        // remove asset
    }

    // deposit and withdraw functions
    function deposit(address token, uint256 amount, address receiver) external nonReentrant whenNotPaused {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");
        require(!pausedAssets[token], "ASSET_PAUSED");
        require(amount > 0, "ZERO_AMOUNT");
        require(receiver != address(0), "INVALID_RECEIVER");

        // convert to base asset
        uint256 baseAssetAmount = convertTokenToBaseAsset(token, amount);

        uint256 sharesToMint = _convertToShares(baseAssetAmount, MathUpgradeable.Rounding.Down);

        // transfer token
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // mint shares
        _mint(receiver, sharesToMint);

        //TODO emit event
    }

    function withdraw(uint256 amount, address token, address receiver) external nonReentrant whenNotPaused {
        require(token != address(0), "INVALID ASSET");
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");
        require(!pausedAssets[token], "ASSET_PAUSED");
        require(amount > 0, "ZERO_AMOUNT");
        require(receiver != address(0), "INVALID_RECEIVER");

        if (canWithdraw(amount, token)) {
            // send to withdrawal queue
            uint256 tokenAmountInBaseAsset = convertTokenToBaseAsset(token, amount);

            uint256 sharesToBurn = _convertToShares(tokenAmountInBaseAsset, MathUpgradeable.Rounding.Up);

            // transfer shares to escrow
            _transfer(msg.sender, wQueues[token], sharesToBurn);

            OmniWithdrawalEscrow(wQueues[token]).registerWithdrawalRequest(receiver, sharesToBurn);

            // TODO: emit event
        }
    }

    // function to check if withdrawal can be resolved now

    function canResolveWithdrawal(uint256 amount, address token) public view returns (bool) {
        uint256 tokenBalance = ERC20(token).balanceOf(address(this));
        if (tokenBalance >= amount && OmniWithdrawalEscrow(wQueues[token]).totalDebt() == 0) {
            return true;
        }
        return false;
    }

    function canWithdraw(uint256 amount, address token) public view returns (bool) {
        // check if user can withdraw
        uint256 _tokenTVL = tokenTVL(token);

        uint256 debtShare = OmniWithdrawalEscrow(wQueues[token]).totalDebt();

        uint256 debtAssetAmount = _convertToAssets(debtShare, MathUpgradeable.Rounding.Up);

        uint256 availableAssets = _tokenTVL - debtAssetAmount;
        return _convertToAssets(amount, MathUpgradeable.Rounding.Up) <= availableAssets;
    }

    // todo implement
    function totalAssets() public view returns (uint256 amount) {
        for (uint256 i = 0; i < assetCount; i++) {
            amount += tokenTVL(assets[i]);
        }
        return amount;
    }

    function tokenTVL(address token) public view returns (uint256 amount) {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");

        uint256 vaultShares = UltraLRT(vaults[token]).balanceOf(address(this));
        uint256 vaultAssets =
            UltraLRT(vaults[token]).convertToAssets(vaultShares) + ERC20(token).balanceOf(address(this));

        // convert to base asset
        if (token != baseAsset) {
            (uint256 rate,) = IPriceFeed(priceFeeds[token]).getPrice();
            amount = ((vaultAssets * rate) / 10 ** ERC20(token).decimals());
        } else {
            amount = vaultAssets;
        }
        return amount;
    }

    function convertTokenToBaseAsset(address token, uint256 tokenAmount) public view returns (uint256) {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");
        (uint256 rate,) = IPriceFeed(priceFeeds[token]).getPrice();
        uint256 amount = ((tokenAmount * rate) / 10 ** ERC20(token).decimals());
        return amount;
    }

    function convertBaseAssetToToken(address token, uint256 baseAssetAmount) public view returns (uint256) {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");
        (uint256 rate,) = IPriceFeed(priceFeeds[token]).getPrice();
        uint256 amount = ((baseAssetAmount * 10 ** ERC20(token).decimals()) / rate);
        return amount;
    }

    function convertToShares(uint256 amount) external view returns (uint256) {
        return _convertToShares(amount, MathUpgradeable.Rounding.Down);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, MathUpgradeable.Rounding.Down);
    }

    function _convertToShares(uint256 _assets, MathUpgradeable.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 shares)
    {
        uint256 supply = totalSupply();
        return (_assets == 0 || supply == 0)
            ? _assets.mulDiv(10 ** decimals(), 10 ** ERC20(baseAsset).decimals(), rounding)
            : _assets.mulDiv(supply, totalAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 assets)
    {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? shares.mulDiv(10 ** ERC20(baseAsset).decimals(), 10 ** decimals(), rounding)
            : shares.mulDiv(totalAssets(), supply, rounding);
    }

    // set fees
    function setFees(uint256 _performanceFeeBps, uint256 _managementFeeBps, uint256 _withdrawalFeeBps)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        // set fees
        performanceFeeBps = _performanceFeeBps;
        managementFeeBps = _managementFeeBps;
        withdrawalFeeBps = _withdrawalFeeBps;
    }

    // set management fee
    function setManagementFeeBps(uint256 _managementFeeBps) external onlyRole(GOVERNANCE_ROLE) {
        // set management fee
        _setManagementFeeBps(_managementFeeBps);
    }

    // set performance fee
    function setPerformanceFeeBps(uint256 _performanceFeeBps) external onlyRole(GOVERNANCE_ROLE) {
        // set performance fee
        _setPerformanceFeeBps(_performanceFeeBps);
    }

    // set withdrawal fee
    function setWithdrawalFeeBps(uint256 _withdrawalFeeBps) external onlyRole(GOVERNANCE_ROLE) {
        // set withdrawal fee
        _setWithdrawalFeeBps(_withdrawalFeeBps);
    }

    function _setManagementFeeBps(uint256 _managementFeeBps) internal {
        // set management fee
        managementFeeBps = _managementFeeBps;
    }

    function _setPerformanceFeeBps(uint256 _performanceFeeBps) internal {
        // set performance fee
        performanceFeeBps = _performanceFeeBps;
    }

    function _setWithdrawalFeeBps(uint256 _withdrawalFeeBps) internal {
        // set withdrawal fee
        withdrawalFeeBps = _withdrawalFeeBps;
    }

    // resolve debt for asset
    // collect asset from vault and resolve debt for user
    function resolveDebt(address[] memory token) external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < token.length; i++) {
            require(vaults[token[i]] != address(0), "ASSET_NOT_SUPPORTED");

            uint256 debtShare = OmniWithdrawalEscrow(wQueues[token[i]]).getDebtToResolve();

            if (debtShare == 0) {
                continue;
            }

            uint256 debtAssetAmount = _convertToAssets(debtShare, MathUpgradeable.Rounding.Up);

            uint256 tokenAmount = convertBaseAssetToToken(token[i], debtAssetAmount);

            if (tokenAmount > ERC20(token[i]).balanceOf(address(this))) {
                continue;
            }
            // TODO: pay partial debt

            // burn shares
            _burn(wQueues[token[i]], debtShare);

            // approve withdrawal escrow
            ERC20(token[i]).safeApprove(wQueues[token[i]], tokenAmount);

            // resolve debt
            OmniWithdrawalEscrow(wQueues[token[i]]).resolveDebtShares(debtShare, tokenAmount);
        }
    }
}
