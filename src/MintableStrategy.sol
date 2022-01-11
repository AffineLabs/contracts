// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { MintableToken } from "./MintableToken.sol";
import { VaultAPI } from "./BaseStrategy.sol";

contract MintableStrategy {
    VaultAPI public vault;
    MintableToken public want;

    constructor(address _vault) {
        vault = VaultAPI(_vault);
        want = MintableToken(vault.token());
        // Give Vault unlimited access
        want.approve(_vault, type(uint256).max);
    }

    function harvestGain(uint256 amount) public {
        want.mint(address(this), amount);
        vault.report(amount, 0, 0);
    }

    function harvestLoss(uint256 amount) public {
        want.burn(amount);
        vault.report(0, amount, balance());
    }

    function balance() public view returns (uint256) {
        return want.balanceOf(address(this));
    }
}
