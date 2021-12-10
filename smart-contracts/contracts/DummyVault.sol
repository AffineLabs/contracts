// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// dummy vault to deploy on kovan
contract DummyVault is ERC20 {
    // this is AAVE's usdc address on kovan
    IERC20 token = IERC20(0xe22da380ee6B445bb8273C81944ADEB6E8450422);
    event Deposit(address indexed user, uint256 numToken, uint256 numShares);
    event Withdraw(address indexed user, uint256 numShares, uint256 numToken);

    constructor() ERC20("Alpine USDC", "alpUSDC") {}

    function balance(address user) public view returns (uint256 usdc, uint256 alpine) {
        usdc = token.balanceOf(user);
        alpine = balanceOf(user);
    }

    function globalTVL() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // We don't need to check if user == msg.sender()
    // So long as this conract can transfer usdc from the given user, everything is fine
    function deposit(address user, uint256 numToken) public {
        // transfer usdc to this contract
        token.transferFrom(user, address(this), numToken);

        // mint
        _mint(user, numToken);
        emit Deposit(user, numToken, numToken);
    }

    function withdraw(address user, uint256 numShares) public {
        // burn
        _burn(user, numShares);
        // transfer usdc out
        token.transfer(user, numShares);
        emit Withdraw(user, numShares, numShares);
    }
}
