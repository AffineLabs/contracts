// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { MintableToken } from "./MintableToken.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { L2Vault } from "../polygon/L2Vault.sol";

contract MintableStrategy is BaseStrategy {
    MintableToken public asset;

    constructor(L2Vault _vault) {
        vault = _vault;
        asset = MintableToken(address(vault.asset()));
        // Give Vault unlimited access
        asset.approve(address(_vault), type(uint256).max);
    }

    function gainAsset(uint256 amount) public {
        asset.mint(address(this), amount);
    }

    function loseAsset(uint256 amount) public {
        asset.burn(amount);
    }

    function balanceOfToken() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function invest(uint256 amount) external pure override {
        amount;
    }

    function divest(uint256 amount) external pure override returns (uint256) {
        amount;
        return 0;
    }

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfToken();
    }
}
