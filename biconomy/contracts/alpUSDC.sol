// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract alpUSDC is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor() ERC20("Alpine USDC", "alpUSDC") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address user, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(user, amount);
    }
}
