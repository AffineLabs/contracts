// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {BaseStrategy} from "../../BaseStrategy.sol";
import {BaseVault} from "../../BaseVault.sol";
import {MockERC20} from "./MockERC20.sol";

contract TestStrategy is BaseStrategy {
    constructor(BaseVault _vault) BaseStrategy(_vault) {}

    function invest(uint256 amount) public override {
        asset.transferFrom(address(vault), address(this), amount);
    }

    function divest(uint256 amount) public virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend);
        return amountToSend;
    }

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset();
    }
}

contract TestStrategyDivestSlippage is TestStrategy {
    constructor(BaseVault _vault) TestStrategy(_vault) {}

    function divest(uint256 amount) public virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend / 2);
        return amountToSend;
    }
}
