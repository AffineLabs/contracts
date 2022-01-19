// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

// A mintable token for easy testing of vaults

// This contract will be used for Goerli/Mumbai USDC
// The two tokens will be mapped (https://docs.polygon.technology/docs/develop/ethereum-polygon/submit-mapping-request)
// Note that there are no access controls since these are just testnet contracts
contract MintableToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mintable USDC", "USDC", 6) {
        _mint(msg.sender, initialSupply);
    }

    // Will be called by root chain manager in Goerli, also by anyone who wants to test vault
    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    // Function to make this a legitimate "child token" that can be burned and minted
    // by the Polygon bridge contracts (https://docs.polygon.technology/docs/develop/ethereum-polygon/mintable-assets/#contract-to-be-deployed-on-polygon-chain)

    function deposit(address user, bytes calldata depositData) external {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
