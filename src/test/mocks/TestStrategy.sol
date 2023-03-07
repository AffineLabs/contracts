// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {DivestType} from "src/libs/DivestType.sol";
import {MockERC20} from "./MockERC20.sol";

contract TestStrategy is BaseStrategy {
    constructor(AffineVault _vault) BaseStrategy(_vault) {}

    function _divest(uint256 amount, DivestType /*divestType*/ ) internal virtual override returns (uint256) {
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

    function _divest(uint256 amount, DivestType /*divestType*/ ) internal virtual override returns (uint256) {
        uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
        asset.transfer(address(vault), amountToSend / 2);
        return amountToSend;
    }
}

contract TestIlliquidStrategy is TestStrategy {
    constructor(AffineVault _vault) TestStrategy(_vault) {}

    function _divest(uint256 amount, DivestType divestType) internal virtual override returns (uint256) {
        if (divestType == DivestType.FORCED) {
            uint256 amountToSend = amount > balanceOfAsset() ? balanceOfAsset() : amount;
            asset.transfer(address(vault), amountToSend);
            return amountToSend;
        } else {
            return 0;
        }
    }
}
