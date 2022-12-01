// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {BaseVault} from "../BaseVault.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";

contract Vault is BaseVault, ERC4626Upgradeable {
    using MathUpgradeable for uint256;

    function initalize(address _governance, address vaultAsset) external virtual initializer {
        BaseVault.baseInitialize(_governance, ERC20(vaultAsset), address(0), BridgeEscrow(address(0)));
        ERC4626Upgradeable.__ERC4626_init(IERC20MetadataUpgradeable(vaultAsset));
    }

    function asset() public view override (BaseVault, ERC4626Upgradeable) returns (address) {
        return BaseVault.asset();
    }

    /// @notice See {IERC4626-totalAssets}
    function totalAssets() public view virtual override returns (uint256) {
        return vaultTVL() - lockedProfit();
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev See {IERC4262-deposit}.
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /**
     * @dev See {IERC4262-mint}.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /**
     * @dev See {IERC4262-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev See {IERC4262-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256 shares)
    {
        uint256 _totalSupply = totalSupply() + 1e8;
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
        uint256 _totalSupply = totalSupply() + 1e8;
        uint256 _totalAssets = totalAssets() + 1;
        return shares.mulDiv(_totalAssets, _totalSupply, rounding);
    }
}
