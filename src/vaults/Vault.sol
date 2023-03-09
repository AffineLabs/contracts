// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {DetailedShare} from "src/utils/Detailed.sol";

import {BaseStrategy as Strategy} from "src/strategies/BaseStrategy.sol";
import {DivestType} from "src/libs/DivestType.sol";

contract Vault is AffineVault, ERC4626Upgradeable, PausableUpgradeable, DetailedShare {
    using SafeTransferLib for ERC20;
    using MathUpgradeable for uint256;

    function initialize(address _governance, address vaultAsset, string memory _name, string memory _symbol)
        external
        initializer
    {
        AffineVault.baseInitialize(_governance, ERC20(vaultAsset));
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20MetadataUpgradeable(vaultAsset));
        _grantRole(GUARDIAN_ROLE, governance);
    }

    function asset() public view override(AffineVault, ERC4626Upgradeable) returns (address) {
        return AffineVault.asset();
    }

    function decimals() public view virtual override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return 18;
    }

    /// @notice See {IERC4626-totalAssets}
    function totalAssets() public view virtual override returns (uint256) {
        return vaultTVL() - lockedProfit();
    }

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");

    /// @notice Pause the contract
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev See {IERC4262-deposit}.
     */
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    /**
     * @dev See {IERC4262-mint}.
     */
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /**
     * @dev See {IERC4262-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 shares = _convertToShares(assets, MathUpgradeable.Rounding.Up);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev See {IERC4262-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        require(shares > 0, "Vault: zero shares");
        _mint(receiver, shares);
        _asset.safeTransferFrom(caller, address(this), assets);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _liquidate(assets);

        // If user tries to withdraw too much, register request on LockedWithdrawalEscrow
        uint256 currAssets = _asset.balanceOf(address(this));
        if (currAssets < assets) {
            uint256 sharesToLock = _convertToShares(assets - currAssets, MathUpgradeable.Rounding.Up);
            // Lock users shares in escrow
            _transfer({from: owner, to: address(debtEscrow), amount: sharesToLock});

            // Register withdrawal request
            debtEscrow.registerWithdrawalRequest(_msgSender(), sharesToLock);

            // Reduce amount of shares that will be burned in this transaction
            shares -= sharesToLock;
            assets = currAssets;
        }

        if (shares == 0 || assets == 0) return;

        uint256 assetsFee = _getWithdrawalFee(assets);
        uint256 assetsToUser = assets - assetsFee;

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);

        _asset.safeTransfer(receiver, assetsToUser);
        _asset.safeTransfer(governance, assetsFee);
    }

    /*//////////////////////////////////////////////////////////////
                             EXCHANGE RATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC4262-previewWithdraw}.
     */
    function previewWithdraw(uint256 assetsToUser) public view virtual override returns (uint256) {
        // assets * ((1 - feeBps) / 1e4) = assetsToUser
        // assets * ((1e4 - feeBps) / 1e4) = assetsToUser
        uint256 assets = assetsToUser.mulDiv(MAX_BPS, MAX_BPS - withdrawalFee, MathUpgradeable.Rounding.Up);
        return _convertToShares(assets, MathUpgradeable.Rounding.Up);
    }

    /**
     * @dev See {IERC4262-previewRedeem}.
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        return assets - _getWithdrawalFee(assets);
    }

    function initialSharesPerAsset() public pure virtual returns (uint256) {
        // E.g. for USDC, we want the initial price of a share to be $100.
        // For an initial price of 1 USDC / share we would have 1e6 * 1e10 / 1 = 1e16 shares.
        // This a 1:0.01 ratio of assets:shares if this vault has 18 decimals
        return 1e10;
    }

    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256 shares)
    {
        uint256 _totalSupply = totalSupply() + initialSharesPerAsset();
        uint256 _totalAssets = totalAssets() + 1;
        return assets.mulDiv(_totalSupply, _totalAssets, rounding);
    }

    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256 assets)
    {
        uint256 _totalSupply = totalSupply() + initialSharesPerAsset();
        uint256 _totalAssets = totalAssets() + 1;
        return shares.mulDiv(_totalAssets, _totalSupply, rounding);
    }

    /*//////////////////////////////////////////////////////////////
                                  FEES
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;

    event ManagementFeeSet(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeSet(uint256 oldFee, uint256 newFee);

    function setManagementFee(uint256 feeBps) external onlyGovernance {
        emit ManagementFeeSet({oldFee: managementFee, newFee: feeBps});
        managementFee = feeBps;
    }

    function setWithdrawalFee(uint256 feeBps) external onlyGovernance {
        emit WithdrawalFeeSet({oldFee: withdrawalFee, newFee: feeBps});
        withdrawalFee = feeBps;
    }

    uint256 constant SECS_PER_YEAR = 365 days;

    function _assessFees() internal virtual override {
        // duration / SECS_PER_YEAR * feebps / MAX_BPS * totalSupply
        uint256 duration = block.timestamp - lastHarvest;

        uint256 feesBps = (duration * managementFee) / SECS_PER_YEAR;
        uint256 numSharesToMint = (feesBps * totalSupply()) / MAX_BPS;

        if (numSharesToMint == 0) {
            return;
        }
        _mint(governance, numSharesToMint);
    }

    /// @dev  Return amount of `asset` to be given to user after applying withdrawal fee
    function _getWithdrawalFee(uint256 assets) internal view virtual returns (uint256) {
        return assets.mulDiv(withdrawalFee, MAX_BPS, MathUpgradeable.Rounding.Up);
    }
    /*//////////////////////////////////////////////////////////////
                           CAPITAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit idle assets into strategies.
    function depositIntoStrategies(uint256 assets) external whenNotPaused onlyRole(HARVESTER) {
        // Leave aside some assets to send to withdrawalEscrow
        if (assets <= pendingDebt) return;
        _depositIntoStrategies(assets - pendingDebt);
    }

    function clearLockedShares() external onlyRole(HARVESTER) {
        // Given a certain amount of pendingDebt, settle the debt by burning the equivalent amount of locked shares
        // and sending the pendingDebt to debtEscrow
        uint256 sharesToBurn = _convertToShares(pendingDebt, MathUpgradeable.Rounding.Up);
        _burn(address(debtEscrow), sharesToBurn);

        // Let debtEscrow know that we have settled a debt
        _asset.transfer(address(debtEscrow), pendingDebt);
        pendingDebt = 0;
        debtEscrow.resolveDebtShares(sharesToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                          DETAILED PRICE INFO
    //////////////////////////////////////////////////////////////*/

    function detailedTVL() external view override returns (Number memory tvl) {
        tvl = Number({num: totalAssets(), decimals: _asset.decimals()});
    }

    function detailedPrice() external view override returns (Number memory price) {
        price = Number({num: convertToAssets(10 ** decimals()), decimals: _asset.decimals()});
    }

    function detailedTotalSupply() external view override returns (Number memory supply) {
        supply = Number({num: totalSupply(), decimals: decimals()});
    }
}
