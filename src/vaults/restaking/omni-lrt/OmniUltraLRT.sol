// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

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

import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";

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
        address _baseAsset,
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

        // set base asset
        baseAsset = _baseAsset;

        // set governance
        governance = _governance;
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
    function addAsset(address asset, address vault, address priceFeed, address escrow)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        // add asset
        require(assetCount < 50, "MAX_ASSETS_REACHED");
        require(vaults[asset] == address(0), "ASSET_EXISTS");

        assetList[assetCount] = asset;
        vaults[asset] = vault;
        wQueues[asset] = escrow; // todo set withdrawal queue
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
        require(vaults[asset] != address(0), "ASSET_NOT_EXISTS");
        require(tokenTVL(asset) < WEI_TOLERANCE, "ASSET_NOT_EMPTY");

        // remove asset
        vaults[asset] = address(0);
        wQueues[asset] = address(0);
        priceFeeds[asset] = address(0);
        pausedAssets[asset] = false;
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

    function investAssets(address[] memory token, uint256[] memory amount) external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < token.length; i++) {
            _invest(token[i], amount[i]);
        }
    }

    /// invest assets
    function _invest(address token, uint256 amount) internal {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");
        require(amount > 0, "ZERO_AMOUNT");
        require(amount <= ERC20(token).balanceOf(address(this)), "INSUFFICIENT_BALANCE");
        // approve token
        ERC20(token).safeApprove(vaults[token], amount);
        // deposit
        UltraLRT(vaults[token]).deposit(amount, address(this));
    }

    // divest assets
    function divestAssets(address[] memory token, uint256[] memory amount) external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < token.length; i++) {
            _divest(token[i], amount[i]);
        }
    }

    function _divest(address token, uint256 amount) internal {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");
        require(amount > 0, "ZERO_AMOUNT");

        // check vault has that amount of shares
        uint256 vaultShares = UltraLRT(vaults[token]).balanceOf(address(this));
        // convert to assets
        uint256 vaultAssets = UltraLRT(vaults[token]).convertToAssets(vaultShares);
        require(vaultAssets >= amount, "INSUFFICIENT_BALANCE");
        // withdraw
        UltraLRT(vaults[token]).withdraw(amount, address(this), address(this));
    }

    // update min vault wq epoch
    function updateMinVaultWqEpoch(address token) external onlyRole(HARVESTER_ROLE) {
        _updateMinVaultWqEpoch(token);
    }

    function _updateMinVaultWqEpoch(address token) internal {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");

        WithdrawalEscrowV2 wq = WithdrawalEscrowV2(UltraLRT(vaults[token]).escrow());
        uint256 currentEpoch = wq.currentEpoch();
        uint256 minEpoch = minVaultWqEpoch[token];

        while (minEpoch < currentEpoch) {
            if (wq.userDebtShare(minEpoch, address(this)) > 0) {
                break;
            }
            minEpoch++;
        }
        minVaultWqEpoch[token] = minEpoch;
    }

    // todo implement
    function totalAssets() public view returns (uint256 amount) {
        for (uint256 i = 0; i < assetCount; i++) {
            amount += tokenTVL(assetList[i]);
        }
        return amount;
    }

    function tokenTVL(address token) public view returns (uint256 amount) {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");

        uint256 vaultShares = UltraLRT(vaults[token]).balanceOf(address(this));

        // get vault wq assets and shares
        (uint256 wqShares, uint256 wqAssets) = getVaultWqTVL(token);

        uint256 vaultAssets = UltraLRT(vaults[token]).convertToAssets(vaultShares + wqShares)
            + ERC20(token).balanceOf(address(this)) + wqAssets;

        // convert to base asset
        if (token != baseAsset) {
            (uint256 rate,) = IPriceFeed(priceFeeds[token]).getPrice();
            amount = ((vaultAssets * rate) / 10 ** ERC20(token).decimals());
        } else {
            amount = vaultAssets;
        }
        return amount;
    }

    function getVaultWqTVL(address token) public view returns (uint256 shares, uint256 assets) {
        require(vaults[token] != address(0), "ASSET_NOT_SUPPORTED");

        WithdrawalEscrowV2 wq = WithdrawalEscrowV2(UltraLRT(vaults[token]).escrow());

        uint256 currentEpoch = wq.currentEpoch();

        for (uint256 i = minVaultWqEpoch[token]; i <= currentEpoch; i++) {
            if (wq.canWithdraw(i)) {
                assets += wq.withdrawableAssets(address(this), i);
            } else {
                shares += wq.userDebtShare(i, address(this));
            }
        }

        return (shares, assets);
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
    function resolveDebt(address[] memory tokens) external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(vaults[tokens[i]] != address(0), "ASSET_NOT_SUPPORTED");

            uint256 debtShare = OmniWithdrawalEscrow(wQueues[tokens[i]]).getDebtToResolve();
            if (debtShare == 0) {
                continue;
            }
            // convert to base asset amount
            uint256 debtAssetAmount = _convertToAssets(debtShare, MathUpgradeable.Rounding.Up);
            // convert to token amount
            uint256 tokenAmount = convertBaseAssetToToken(tokens[i], debtAssetAmount);

            // check token valt share
            uint256 investedTokenAmount =
                UltraLRT(vaults[tokens[i]]).convertToAssets(UltraLRT(vaults[tokens[i]]).balanceOf(address(this)));
            bool payPartialDebt;
            // if we have less token now and have token invested
            if (tokenAmount > ERC20(tokens[i]).balanceOf(address(this))) {
                if (investedTokenAmount < WEI_TOLERANCE) {
                    // out of assets so pay partial debt
                    payPartialDebt = true;
                } else {
                    continue;
                }
            }
            // TODO: event pay partial debt

            if (payPartialDebt) {
                // get debt shares for token amount
                debtAssetAmount = convertTokenToBaseAsset(tokens[i], ERC20(tokens[i]).balanceOf(address(this)));
                tokenAmount = ERC20(tokens[i]).balanceOf(address(this));
                debtShare = _convertToShares(debtAssetAmount, MathUpgradeable.Rounding.Up);
                // enable share withdrawal from wq
                OmniWithdrawalEscrow(wQueues[tokens[i]]).enableShareWithdrawal();
            }
            // burn shares
            _burn(wQueues[tokens[i]], debtShare);

            // approve withdrawal escrow
            ERC20(tokens[i]).safeApprove(wQueues[tokens[i]], tokenAmount);

            // resolve debt
            OmniWithdrawalEscrow(wQueues[tokens[i]]).resolveDebtShares(debtShare, tokenAmount);
        }
    }

    // disable share withdrawal
    function disableShareWithdrawal(address[] memory token) external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < token.length; i++) {
            require(vaults[token[i]] != address(0), "ASSET_NOT_SUPPORTED");
            OmniWithdrawalEscrow(wQueues[token[i]]).disableShareWithdrawal();
        }
    }

    // end epoch
    function endEpoch(address[] memory tokens, bool doWithdrawalRequest) external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(vaults[tokens[i]] != address(0), "ASSET_NOT_SUPPORTED");

            uint256 closingEpoch = OmniWithdrawalEscrow(wQueues[tokens[i]]).currentEpoch();

            OmniWithdrawalEscrow(wQueues[tokens[i]]).endEpoch();

            if (OmniWithdrawalEscrow(wQueues[tokens[i]]).currentEpoch() == closingEpoch) {
                // nothing to close
                continue;
            }

            if (doWithdrawalRequest) {
                (uint256 shares,,) = OmniWithdrawalEscrow(wQueues[tokens[i]]).epochInfo(closingEpoch);
                uint256 debtAssets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
                uint256 debtTokenAmount = convertBaseAssetToToken(tokens[i], debtAssets);
                // check vault has that amount of shares
                uint256 vaultShares = UltraLRT(vaults[tokens[i]]).balanceOf(address(this));
                // convert to assets
                uint256 vaultAssets = UltraLRT(vaults[tokens[i]]).convertToAssets(vaultShares);

                uint256 maxWithdrawalAmount = MathUpgradeable.min(debtTokenAmount, vaultAssets);
                // withdraw
                UltraLRT(vaults[tokens[i]]).withdraw(maxWithdrawalAmount, address(this), address(this));
            }
        }
    }
}
