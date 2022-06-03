// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { MintableToken } from "./MintableToken.sol";
import { BaseVault } from "../BaseVault.sol";

contract MintableStrategy {
    BaseVault public vault;
    MintableToken public want;

    constructor(BaseVault _vault) {
        vault = _vault;
        want = MintableToken(address(vault.asset()));
        // Give Vault unlimited access
        want.approve(address(_vault), type(uint256).max);
    }

    function harvestGain(uint256 amount) public {
        // want.mint(address(this), amount);
        // vault.report(amount, 0, 0);
    }

    function harvestLoss(uint256 amount) public {
        // want.burn(amount);
        // vault.report(0, amount, balance());
    }

    function balance() public view returns (uint256) {
        return want.balanceOf(address(this));
    }
}
