// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {L2AAVEStrategy} from "../polygon/L2AAVEStrategy.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";

contract AAVEStratTest is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
    L2AAVEStrategy strategy;
    // Mumbai USDC that AAVE takes in
    ERC20 usdc = ERC20(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e);

    function setUp() public {
        vm.createSelectFork("mumbai", 25_804_436);
        vault = Deploy.deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L2AAVEStrategy(
            vault,
            0xE6ef11C967898F9525D550014FDEdCFAB63536B5 // aave adress provider registry
        );
        vm.prank(governance);
        vault.addStrategy(strategy, 5000);
    }

    function testStrategyMakesMoney() public {
        // Vault deposits half of its tvl into the strategy
        // Give us (this contract) 1 USDC. Deposit into vault.
        // This testnet usdc has a totalSupply of  the max uint256, so we set `adjust` to false
        deal(address(usdc), address(this), 1e6, false);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1e6, address(this));

        vm.startPrank(governance);
        vault.depositIntoStrategies(1e6);
        vm.stopPrank();

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
    }
}
