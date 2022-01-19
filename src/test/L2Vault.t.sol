// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ERC20User } from "./ERC20User.sol";
import { L2Vault } from "../polygon-contracts/L2Vault.sol";
import { Create2Deployer } from "./Create2Deployer.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";

contract VaultTest is DSTest {
    L2Vault vault;
    MockERC20 token;
    ERC20User user;
    Create2Deployer create2Deployer;

    function setUp() public {
        token = new MockERC20("Mock", "MT", 18);
        create2Deployer = new Create2Deployer();
        vault = new L2Vault(
            address(0), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            create2Deployer, // create2deployer (needs to be a real contract)
            1, // l1 ratio
            1 // l2 ratio
        );
        user = new ERC20User(token);
    }

    function testDepositWithdraw(uint256 amountToken) public {
        token.mint(address(user), amountToken);

        // user gives max approval to vault for token
        user.approve(address(vault), type(uint256).max);
        vault.deposit(address(user), amountToken);
        // If vault is empty, tokens are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(address(user));
        assertEq(numShares, amountToken);
        assertEq(token.balanceOf(address(user)), 0);

        vault.withdraw(address(user), numShares);
        assertEq(vault.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(user)), amountToken);

        // TODO: invariant testing
        // Invariant:  // The amount of shares I get is determined by numToken * (totalshares/totaltokens)
    }
}
