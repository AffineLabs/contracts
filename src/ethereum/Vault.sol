// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {BaseVault} from "../BaseVault.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {Affine4626} from "../Affine4626.sol";

contract Vault is BaseVault, Affine4626 {
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
}
