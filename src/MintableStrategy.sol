// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface VaultAPI {
    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external returns (uint256);

    function token() external returns (address);
}

interface TokenAPI is IERC20 {
    function mint(address user, uint256 amount) external;

    function burn(address user, uint256 amount) external;
}

contract MintableStrategy {
    VaultAPI public vault;
    TokenAPI public want;

    constructor(address _vault) {
        vault = VaultAPI(_vault);
        want = TokenAPI(vault.token());
        // Give Vault unlimited access
        want.approve(_vault, type(uint256).max);
    }

    function harvestGain(uint256 amount) public {
        want.mint(address(this), amount);
        vault.report(amount, 0, 0);
    }

    function harvestLoss(uint256 amount) public {
        want.burn(address(this), amount);
        vault.report(0, amount, balance());
    }

    function balance() public view returns (uint256) {
        return want.balanceOf(address(this));
    }
}
