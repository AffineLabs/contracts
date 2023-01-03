// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {AffineVault} from "../AffineVault.sol";
import {Affine4626} from "../Affine4626.sol";
import {DetailedShare} from "../both/Detailed.sol";

contract Vault is AffineVault, Affine4626, DetailedShare {
    function initialize(address _governance, address vaultAsset) external initializer {
        AffineVault.baseInitialize(_governance, ERC20(vaultAsset));
        __ERC20_init("USD Earn", "usdEarn");
        ERC4626Upgradeable.__ERC4626_init(IERC20MetadataUpgradeable(vaultAsset));
    }

    function asset() public view override (AffineVault, ERC4626Upgradeable) returns (address) {
        return AffineVault.asset();
    }

    /// @notice See {IERC4626-totalAssets}
    function totalAssets() public view virtual override returns (uint256) {
        return vaultTVL() - lockedProfit();
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
