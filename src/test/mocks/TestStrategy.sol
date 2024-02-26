// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {MockERC20} from "./MockERC20.sol";

contract TestStrategy is BaseStrategy {
    constructor(AffineVault _vault) BaseStrategy(_vault) {}

    function _divest(uint256 amount) internal virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend);
        return amountToSend;
    }

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset();
    }
}

contract TestStrategyDivestSlippage is TestStrategy {
    constructor(AffineVault _vault) TestStrategy(_vault) {}

    function _divest(uint256 amount) internal virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend / 2);
        return amountToSend;
    }
}
