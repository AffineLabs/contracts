// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { IHevm } from "./IHevm.sol";
import "forge-std/src/stdlib.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { L2AAVEStrategy } from "../polygon/L2AAVEStrategy.sol";
import { Deploy } from "./Deploy.sol";

// TODO: make it so that the first test always works => Truncation means the assert will fail at some blocks
contract L2AAVEStratTestFork is DSTest {
    L2Vault vault;
    L2AAVEStrategy strategy;
    // Mumbai USDC that AAVE takes in
    ERC20 usdc = ERC20(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e);
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    StdStorage stdstore;
    using stdStorage for StdStorage;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("token()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        hevm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L2AAVEStrategy(
            vault,
            0xE6ef11C967898F9525D550014FDEdCFAB63536B5, // aave adress provider registry
            0x0a1AB7aea4314477D40907412554d10d30A0503F, // dummy incentives controller
            0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff, // sushiswap router on mumbai
            0x5B67676a984807a212b1c59eBFc9B3568a474F0a, // reward token -> wrapped matic
            0x5B67676a984807a212b1c59eBFc9B3568a474F0a // wrapped matic address
        );
    }

    function testStrategyMakesMoney() public {
        // Give the Vault  1 usdc
        // storage slot of addr's balance is keccak256(bytes32(addr) . p) where p is 0
        // See https://docs.soliditylang.org/en/v0.8.10/internals/layout_in_storage.html#mappings-and-dynamic-arrays
        // Also see https://mumbai.polygonscan.com/address/0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e#code
        // and note that _balances occupies the first storage slot

        // abi encoding pads the address to 32 bytes before concatenating
        bytes memory h_of_k_dot_p = abi.encode(address(vault), 0);
        hevm.store(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e, keccak256(h_of_k_dot_p), bytes32(uint256(1e6)));

        // This contract is the governance address so this will work
        vault.addStrategy(strategy);

        // Deposit 0.5 usdc into aave with depositIntoStrategy
        vault.depositIntoStrategy(strategy, 1e6 / 2);

        // Go 10 days into the future and make sure that the vault makes money
        hevm.warp(block.timestamp + 10 days);

        uint256 profit = strategy.aToken().balanceOf(address(strategy)) - 1e6 / 2;
        assertGe(profit, 100);
    }

    function testStrategyLosesMoney() public {
        bytes memory h_of_k_dot_p = abi.encode(address(vault), 0);
        hevm.store(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e, keccak256(h_of_k_dot_p), bytes32(uint256(1e6)));

        vault.addStrategy(strategy);

        // Deposit 0.5 usdc into aave with depositIntoStrategy
        vault.depositIntoStrategy(strategy, 1e6);

        // Impersonate strategy
        hevm.startPrank(address(strategy));
        // withdraw from lending pool
        // Lose money by withdrawing lent USDC to the USDC contract
        strategy.lendingPool().withdraw(address(strategy.token()), 1e6 / 2, address(usdc));
        hevm.stopPrank();

        vault.withdrawFromStrategy(strategy, 1e6 / 2);
        assertEq(usdc.balanceOf(address(vault)), 1e6 / 2);
    }
}
