// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Test Token", "TT") {
        _mint(msg.sender, initialSupply);
    }

    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) public {
        _burn(user, amount);
    }

    function decimals() public pure override returns (uint8) {
        // imitating usdc
        return 6;
    }
}
