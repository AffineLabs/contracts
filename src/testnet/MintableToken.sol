// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { EIP712MetaTransaction } from "../../lib/EIP712MetaTransaction.sol";

// A mintable token for easy testing of vaults

// This contract will be used for Goerli/Mumbai USDC
// The two tokens will be mapped (https://docs.polygon.technology/docs/develop/ethereum-polygon/submit-mapping-request)
// Note that there are no access controls since these are just testnet contracts
contract MintableToken is ERC20, EIP712MetaTransaction {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 numDecimals,
        uint256 initialSupply
    ) ERC20(_name, _symbol) EIP712MetaTransaction(_name, "1") {
        _mint(msg.sender, initialSupply);
        _decimals = numDecimals;
    }

    uint8 internal _decimals;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _msgSender() internal view override(Context, EIP712MetaTransaction) returns (address) {
        return EIP712MetaTransaction._msgSender();
    }

    // Will be called by root chain manager in Goerli, also by anyone who wants to test vault
    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    // Function to make this a legitimate "child token" that can be burned and minted by the Polygon bridge contracts
    // solhint-disable-next-line max-line-length
    // (https://docs.polygon.technology/docs/develop/ethereum-polygon/mintable-assets/#contract-to-be-deployed-on-polygon-chain)
    function deposit(address user, bytes calldata depositData) external {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
}
