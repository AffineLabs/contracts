// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {SDaiStrategy} from "src/strategies/SDaiStrategy.sol";

/// @dev deployed on Dec 13,23 for test

contract TestSDaiStrategy is SDaiStrategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(AffineVault _vault, address[] memory strategists) SDaiStrategy(_vault, strategists) {}

    function divestByStrategist(uint256 amount) external onlyRole(STRATEGIST_ROLE) returns (uint256) {
        // tvl
        uint256 tvl = _investedAssets();

        // ratio of sdai to withdraw
        uint256 sDaiToWithdraw =
            amount < tvl ? SDAI.balanceOf(address(this)).mulDivDown(amount, tvl) : SDAI.balanceOf(address(this));

        uint256 receivedDai = SDAI.redeem(sDaiToWithdraw, address(this), address(this));
        uint256 prevAssets = asset.balanceOf(address(this));
        _swapDaiToAsset(receivedDai);
        uint256 receivedAssets = asset.balanceOf(address(this)) - prevAssets;
        asset.safeTransfer(msg.sender, receivedAssets);
        return receivedAssets;
    }
}
