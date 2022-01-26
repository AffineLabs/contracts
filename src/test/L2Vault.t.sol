// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { IHevm } from "./IHevm.sol";
import { MockERC20 } from "./MockERC20.sol";
import { L2Vault } from "../polygon-contracts/L2Vault.sol";
import { Relayer } from "../polygon-contracts/Relayer.sol";
import { Create2Deployer } from "./Create2Deployer.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";

contract VaultTest is DSTest {
    L2Vault vault;
    MockERC20 token;
    Create2Deployer create2Deployer;
    Relayer relayer;

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
            1, // l2 ratio
            address(0) // trusted fowarder
        );
        relayer = vault.relayer();
    }

    function testDepositWithdraw(uint256 amountToken) public {
        address user = address(this);
        token.mint(user, amountToken);

        // user gives max approval to vault for token
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amountToken);

        // If vault is empty, tokens are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(user);
        assertEq(numShares, amountToken);
        assertEq(token.balanceOf(address(user)), 0);

        vault.withdraw(numShares);
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function testDepositWithdrawGasLess() public {
        address user = address(this);
        token.mint(user, 1e18);

        token.approve(address(vault), type(uint256).max);

        // truster forwarder is zero address and is the one who calls deposit on the relayer
        hevm.startPrank(address(0));
        // When the relayer calls msgSender(), it will return the address of the user now
        hevm.mockCall(address(relayer), abi.encodeWithSelector(bytes4(0xd737d0c7)), abi.encode(user));

        relayer.deposit(1e18);
        assertEq(vault.balanceOf(user), 1e18);

        relayer.withdraw(1e18);
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), 1e18);

        // Only the forwarder can make calls to the relayer
        hevm.stopPrank();
        hevm.expectRevert(bytes("Forwarder only"));
        relayer.deposit(1e18);
        hevm.expectRevert(bytes("Forwarder only"));
        relayer.withdraw(1e18);

        // only the relayer can call deposit gasless
        hevm.expectRevert(bytes("Only relayer"));
        vault.depositGasLess(user, 1e18);
        hevm.expectRevert(bytes("Only relayer"));
        vault.withdrawGasLess(user, 1e18);
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
