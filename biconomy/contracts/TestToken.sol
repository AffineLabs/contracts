// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Test Token", "TT") {
        _mint(msg.sender, initialSupply);
    }
}
