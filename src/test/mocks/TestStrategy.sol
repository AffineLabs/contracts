// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {BaseStrategy} from "../../BaseStrategy.sol";
import {AffineStrategy} from "../../AffineStrategy.sol";
import {BaseVault} from "../../BaseVault.sol";
import {AffineVault} from "../../AffineVault.sol";
import {MockERC20} from "./MockERC20.sol";
import {Vault} from "../../both/Vault.sol";

contract TestStrategy is BaseStrategy {
    constructor(BaseVault _vault) BaseStrategy(_vault) {}

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
    constructor(BaseVault _vault) TestStrategy(_vault) {}

    function _divest(uint256 amount) internal virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend / 2);
        return amountToSend;
    }
}

contract TestStrategyForEthVault is AffineStrategy {
    constructor(AffineVault _vault) AffineStrategy(_vault) {}

    function _divest(uint256 amount) internal virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend);
        return amountToSend;
    }

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset();
    }
}
