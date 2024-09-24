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

contract OmniUltraLRT is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    OmniUltraLRTStorage
{
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
        //todo deposit
    }

    function withdraw(uint256 shares, address token, address receiver) external nonReentrant whenNotPaused {
        //todo withdraw
    }

    // todo implement
    function tvl() external view returns (uint256) {
        // tvl
        for (uint256 i = 0; i < assetCount; i++) {
            // get price feed
            // get balance
            // get price
            // calculate tvl
        }
        return 0;
    }

    function convertToShares(uint256 amount) external view returns (uint256) {
        // convert to shares
        return 0;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        // convert to assets
        return 0;
    }

    function _convertToShares(uint256 _assets, MathUpgradeable.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 shares)
    {
        // uint256 supply = totalSupply();
        // return
        //     (_assets == 0 || supply == 0)
        //         ? _assets.mulDiv(10**decimals(), 10**_asset.decimals(), rounding)
        //         : _assets.mulDiv(supply, totalAssets(), rounding);
        return 0;
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
        // uint256 supply = totalSupply();
        // return
        //     (supply == 0)
        //         ? shares.mulDiv(10**_asset.decimals(), 10**decimals(), rounding)
        //         : shares.mulDiv(totalAssets(), supply, rounding);
        return 0;
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
    function resolveDebt(address[] memory assets) external onlyRole(HARVESTER_ROLE) {
        // resolve debt
    }
}
