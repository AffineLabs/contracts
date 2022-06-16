// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/tokens/ERC20.sol";

// dummy vault to deploy on kovan
contract DummyVault is ERC20 {
    // this is AAVE's usdc address on kovan
    ERC20 token = ERC20(0xe22da380ee6B445bb8273C81944ADEB6E8450422);
    event Deposit(address indexed user, uint256 numToken, uint256 numShares, uint256 price);
    event Withdraw(address indexed user, uint256 numShares, uint256 numToken, uint256 price);

    uint256 public price;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _price
    ) ERC20(name, symbol, token.decimals()) {
        price = _price;
    }

    function balance(address user) public view returns (uint256 bal) {
        // balance in usdc
        bal = price * balanceOf[user];
    }

    function globalTVL() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function deposit(address user, uint256 numToken) public {
        // transfer usdc to this contract
        token.transferFrom(user, address(this), numToken);

        // price = usdc / share

        uint256 numShares = numToken / price;
        // mint
        _mint(user, numShares);
        emit Deposit(user, numToken, numShares, price);
    }

    function withdraw(address user, uint256 numShares) public {
        // burn
        _burn(user, numShares);
        // transfer usdc out
        uint256 numToken = numShares * price;
        token.transfer(user, numToken);
        emit Withdraw(user, numToken, numShares, price);
    }
}
