// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ERC20User } from "./ERC20User.sol";
import { L2Vault } from "../polygon-contracts/L2Vault.sol";
import { Create2Deployer } from "./Create2Deployer.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";

interface IHevm {
    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) external;
}

contract VaultTest is DSTest {
    L2Vault vault;
    MockERC20 token;
    Create2Deployer create2Deployer;

    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

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
    }

    function testDepositWithdraw(uint256 amountToken) public {
        address user = address(this);
        token.mint(user, amountToken);

        // user gives max approval to vault for token
        token.approve(address(vault), type(uint256).max);
        vault.deposit(user, amountToken);

        // If vault is empty, tokens are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(user);
        assertEq(numShares, amountToken);
        assertEq(token.balanceOf(address(user)), 0);

        vault.withdraw(user, numShares);
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function invariantDebtLessThanMaxBPS() public {
        // probably want to give this contract some underlying first
        assertLe(vault.debtRatio(), vault.MAX_BPS());
    }

    // TODO: Get the below test to pass
    // function testShareTokenConversion(
    //     uint256 amountToken,
    //     uint256 totalShares,
    //     uint256 totalTokens
    // ) public {
    //     // update vaults total supply (number of shares)
    //     // storage slots can be found in dapptools' abi output
    //     hevm.store(address(vault), bytes32(uint256(2)), bytes32(totalShares));
    //     emit log_named_uint("foo", vault.totalSupply());

    //     // update vaults total underlying tokens  => could just overwrite storage as well
    //     token.mint(address(vault), totalTokens);

    //     assertEq(vault.tokensFromShares(vault.sharesFromTokens(amountToken)), amountToken);
    // }
}
