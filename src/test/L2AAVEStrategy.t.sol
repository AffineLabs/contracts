// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { IHevm } from "./IHevm.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { L2Vault } from "../polygon-contracts/L2Vault.sol";
import { Create2Deployer } from "./Create2Deployer.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { L2AAVEStrategy } from "../polygon-contracts/L2AAVEStrategy.sol";

// TODO: make it so that the first test always works => Truncation means the assert will fail at some blocks
contract L2AAVEStratTestFork is DSTest {
    L2Vault vault;
    Create2Deployer create2Deployer;
    L2AAVEStrategy strategy;
    ERC20 usdc = ERC20(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e);
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        create2Deployer = new Create2Deployer();
        vault = new L2Vault();
        vault.initialize(
            address(this), // governance
            ERC20(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e), // token -> Mumbai USDC that AAVE takes in
            IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20), // wormhole
            create2Deployer, // create2deployer (needs to be a real contract)
            1, // l1 ratio
            1, // l2 ratio
            address(0), // relayer for gasless transactions
            0
        );
        strategy = new L2AAVEStrategy(
            address(vault),
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
        vault.addStrategy(strategy, 5000, 0, type(uint256).max);

        strategy.harvest();

        // After calling harvest for the first time, we take 5000/10000 percentage of the vaults assets
        assertEq(usdc.balanceOf(address(vault)), 1e6 / 2);
        assertEq(vault.totalDebt(), 1e6 / 2);

        // Strategy deposits all of usdc into AAVE
        assertEq(strategy.aToken().balanceOf(address(strategy)), 1e6 / 2);

        (, , , , , uint256 totalDebt, , ) = vault.strategies(strategy);
        assertEq(totalDebt, 1e6 / 2);

        // Go 10 days into the future and make sure that the vault makes money
        hevm.warp(block.timestamp + 10 days);

        uint256 profit = strategy.aToken().balanceOf(address(strategy)) - 1e6 / 2;
        assertGe(profit, 100);

        // The vault starts with `A` assets. After we send our profit,
        // the vault has `A + profit` assests.
        strategy.harvest();
        assertEq(usdc.balanceOf(address(vault)), 1e6 / 2 + profit);

        // In order for the strategy to take back the profit it just sent to vault, it must call harvest again
        // The vault began with `A` in assets. After last harvest(), the vault has `A + profit` assets
        // Strategy already has a debt of A/2, so will take out profit / 2 in credit to get half of the vault's assets
        strategy.harvest();
        uint256 aTokenBal2 = strategy.aToken().balanceOf(address(strategy));
        assertEq(aTokenBal2, (1e6 + profit) / 2);
    }

    function testStrategyLosesMoney() public {
        bytes memory h_of_k_dot_p = abi.encode(address(vault), 0);
        hevm.store(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e, keccak256(h_of_k_dot_p), bytes32(uint256(1e6)));

        vault.addStrategy(strategy, 5000, 0, type(uint256).max);
        strategy.harvest();

        // Impersonate strategy
        hevm.startPrank(address(strategy));
        // withdraw from lending pool
        // transfer tokens to usdc contract
        strategy.lendingPool().withdraw(address(strategy.want()), 1e6 / 2, address(usdc));
        hevm.stopPrank();

        // assert that vault sets its loss stats correctly
        strategy.harvest();
        // Vault has 0.5 usdc, and strategy immediately takes out half of it.
        // TODO: Reconsider allowing a strategy that has lost money to take more money out
        assertEq(vault.totalDebt(), 1e6 / 4);
        (, , , , , uint256 totalDebt, , uint256 totalLoss) = vault.strategies(strategy);
        assertEq(totalLoss, 1e6 / 2);
        assertEq(totalDebt, 1e6 / 4);
    }
}
