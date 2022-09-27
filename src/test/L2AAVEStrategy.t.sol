// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {L2AAVEStrategy} from "../polygon/L2AAVEStrategy.sol";
import {Deploy} from "./Deploy.sol";

import {Create3Deployer} from "../Create3Deployer.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";

contract AAVEStratTest is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
    L2AAVEStrategy strategy;
    // Mumbai USDC that AAVE takes in
    ERC20 usdc = ERC20(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e);

    

    function setUp() public {
        vm.createSelectFork("polygon", 33647841);
        vault = Deploy.deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        // strategy = new L2AAVEStrategy(
        //     vault,
        //     0xE6ef11C967898F9525D550014FDEdCFAB63536B5, // aave adress provider registry
        //     0x0a1AB7aea4314477D40907412554d10d30A0503F, // dummy incentives controller
        //     0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff, // quickswap router on mumbai
        //     0x5B67676a984807a212b1c59eBFc9B3568a474F0a, // reward token -> wrapped matic
        //     0x5B67676a984807a212b1c59eBFc9B3568a474F0a // wrapped matic address
        // );
        // vm.prank(governance);
        // vault.addStrategy(strategy, 5000);
    }

    function testTemp() public {
        Create3Deployer deployer1 = Create3Deployer(0x5185fe072f9eE947bF017C7854470e11C2cFb32a);
        bytes32 salt = keccak256("who that");
    
        address escrow = deployer1.deploy(
            salt, abi.encodePacked(type(BridgeEscrow).creationCode, abi.encode(address(vault), address(0))), 0
        );
        emit log_named_address("token addr in escrow", address(BridgeEscrow(escrow).token()));
    }

    function testStrategyMakesMoney() public {
        // Vault deposits half of its tvl into the strategy
        // Give us (this contract) 1 USDC. Deposit into vault.
        // This testnet usdc has a totalSupply of  the max uint256, so we set `adjust` to false
        deal(address(usdc), address(this), 1e6, false);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1e6, address(this));

        // Go 10 days into the future and make sure that the vault makes money
        vm.warp(block.timestamp + 10 days);

        uint256 profit = strategy.aToken().balanceOf(address(strategy)) - 1e6 / 2;
        assertGe(profit, 100);
    }

    function testStrategyDivestsOnlyAmountNeeded() public {
        // If the strategy already already has money, we only withdraw amountRequested - current money

        // Give the strategy 1 usdc and 2 aToken
        deal(address(usdc), address(strategy), 3e6, false);

        // NOTE: deal does not work with aTokens, so we need to deposit into the lending pool to get aTokens
        // See https://github.com/foundry-rs/forge-std/issues/140
        vm.startPrank(address(strategy));
        strategy.lendingPool().deposit(address(usdc), 2e6, address(strategy), 0);

        // Divest to get 2 usdc back to vault
        changePrank(address(vault));
        strategy.divest(2e6);

        // We only withdrew 2 - 1 == 1 aToken. We gave 1 usdc and 1 aToken to the vault
        assertEq(usdc.balanceOf(address(vault)), 2e6);
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertEq(strategy.aToken().balanceOf(address(strategy)), 1e6);
    }

    function testTVL() public {
        // Give the strategy 3 usdc
        deal(address(usdc), address(strategy), 3e6, false);

        assertEq(strategy.totalLockedValue(), 3e6);

        vm.startPrank(address(strategy));
        strategy.lendingPool().deposit(address(usdc), 2e6, address(strategy), 0);

        assertEq(strategy.totalLockedValue(), 3e6);

        // TODO: Make sure rewards get tested as well
    }
}
