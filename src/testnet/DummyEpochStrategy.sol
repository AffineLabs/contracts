// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

/// @notice Dummy strategy which does nothing.
contract DummyEpochStrategy is AccessStrategy {
    StrategyVault public immutable sVault;

    constructor(StrategyVault _vault, address[] memory strategists)
        AccessStrategy(AffineVault(address(_vault)), strategists)
    {
        sVault = StrategyVault(address(_vault));
        ERC20(sVault.asset()).approve(address(_vault), type(uint256).max);
    }

    function beginEpoch() external onlyRole(STRATEGIST_ROLE) {
        sVault.beginEpoch();
    }

    function endEpoch() external onlyRole(STRATEGIST_ROLE) {
        sVault.endEpoch();
    }

    /// @notice Updates the tvl.
    /// @dev We could simply call `endEpoch` repeatedly to udpate the tvl, but that would lead to misleading events.
    function beginAndEndEpoch() external onlyRole(STRATEGIST_ROLE) {
        sVault.beginEpoch();
        sVault.endEpoch();
    }

    function totalLockedValue() external view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _divest(uint256 amount) internal virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend);
        return amountToSend;
    }
}
