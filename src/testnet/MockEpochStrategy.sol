// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {MockERC20} from "./MockERC20.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

contract MockEpochStrategy is AccessStrategy {
    StrategyVault public immutable sVault;

    constructor(StrategyVault _vault, address[] memory strategists)
        AccessStrategy(AffineVault(address(_vault)), strategists)
    {
        sVault = StrategyVault(address(_vault));
    }

    function mint(uint256 amount) external onlyRole(STRATEGIST_ROLE) {
        MockERC20(address(asset)).mint(address(this), amount);
    }

    function beginEpoch() external onlyRole(STRATEGIST_ROLE) {
        sVault.beginEpoch();
    }

    function endEpoch() external onlyRole(STRATEGIST_ROLE) {
        MockERC20(address(asset)).mint(address(this), 10 ** asset.decimals());
        sVault.endEpoch();
    }

    function totalLockedValue() external view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
