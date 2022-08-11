// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { BaseStrategy } from "../../BaseStrategy.sol";
import { BaseVault } from "../../BaseVault.sol";
import { MockERC20 } from "./MockERC20.sol";

contract TestStrategy is BaseStrategy {
    constructor(MockERC20 _token, BaseVault _vault) {
        asset = _token;
        vault = _vault;
    }

    function balanceOfAsset() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function invest(uint256 amount) public override {
        asset.transferFrom(address(vault), address(this), amount);
    }

    function divest(uint256 amount) public override returns (uint256) {
        asset.transfer(address(vault), amount);
        return amount;
    }

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset();
    }
}
