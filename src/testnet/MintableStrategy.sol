// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";

import { MintableToken } from "./MintableToken.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { L2Vault } from "../polygon/L2Vault.sol";

contract MintableStrategy is BaseStrategy {
    using SafeTransferLib for ERC20;

    constructor(L2Vault _vault) {
        vault = _vault;
        asset = ERC20(vault.asset());
        // Give Vault unlimited access
        asset.approve(address(_vault), type(uint256).max);
    }

    function gainAsset(uint256 amount) public {
        MintableToken(address(asset)).mint(address(this), amount);
    }

    function loseAsset(uint256 amount) public {
        MintableToken(address(asset)).burn(amount);
    }

    function balanceOfAsset() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function divest(uint256 amount) external override returns (uint256) {
        asset.transfer(address(vault), amount);
        return amount;
    }

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset();
    }
}
