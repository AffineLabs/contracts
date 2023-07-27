// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Vault} from "src/vaults/Vault.sol";
import {NftGate} from "src/vaults/NftGate.sol";

contract VaultV2 is Vault, NftGate {
    using SafeTransferLib for ERC20;
    using MathUpgradeable for uint256;

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        _checkNft(receiver);
        require(shares > 0, "Vault: zero shares");
        _mint(receiver, shares);
        _asset.safeTransferFrom(caller, address(this), assets);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _getWithdrawalFee(uint256 assets, address owner) internal view virtual override returns (uint256) {
        uint256 feeBps;
        if (nftDiscountActive && accessNft.balanceOf(owner) > 0) {
            feeBps = withdrawalFeeWithNft;
        } else {
            feeBps = withdrawalFee;
        }
        return assets.mulDiv(feeBps, MAX_BPS, MathUpgradeable.Rounding.Up);
    }
}
