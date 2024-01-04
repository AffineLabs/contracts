// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {CommonVaultTest} from "src/test/CommonVault.t.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {TestStrategy} from "./mocks/TestStrategy.sol";

import {VaultV2} from "src/vaults/VaultV2.sol";
import {ProfitReserveVaultV2} from "src/vaults/ProfitReserveVaultV2.sol";

import {console2} from "forge-std/console2.sol";

contract ProfitReserveVaultV2Test is CommonVaultTest {
    ProfitReserveVaultV2 profResVault;

    function setUp() public override {
        asset = new MockERC20("Mock", "MT", 6);

        profResVault = new ProfitReserveVaultV2();
        vault = VaultV2(address(profResVault));
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");
    }

    function _getStrategy() internal override returns (BaseStrategy) {
        BaseStrategy strategy = new TestStrategy(vault);
        vm.prank(governance);
        vault.addStrategy(strategy, 10_000);
        return strategy;
    }

    function testSetProfitReserveBps() public {
        vm.expectRevert("Only Governance.");
        profResVault.setProfitReserveBps(5000);
        vm.prank(governance);
        profResVault.setProfitReserveBps(5000);
    }

    function testReservedProfit() public {
        uint256 initialAssets = 100 * (10 ** asset.decimals());
        BaseStrategy strategy = _getStrategy();

        vm.prank(governance);
        profResVault.setProfitReserveBps(5000);

        _giveAssets(alice, initialAssets);

        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        vm.startPrank(governance);

        vault.depositIntoStrategy(strategy, initialAssets);

        assertEq(vault.vaultTVL(), initialAssets);

        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = strategy;

        _giveAssets(address(strategy), initialAssets);
        vm.warp(block.timestamp + 1 days);
        vault.harvest(strategies);
        console2.log("tvl %s", vault.vaultTVL());
        assertEq(vault.vaultTVL(), initialAssets + (initialAssets / 2));

        _giveAssets(address(strategy), initialAssets);
        vm.warp(block.timestamp + 1 days);
        vault.harvest(strategies);
        console2.log("tvl %s", vault.vaultTVL());
        assertEq(vault.vaultTVL(), initialAssets + (initialAssets / 2) + (3 * (initialAssets / 4)));

        profResVault.setProfitReserveBps(0);

        vm.warp(block.timestamp + 1 days);
        vault.harvest(strategies);
        console2.log("tvl %s", vault.vaultTVL());
        assertEq(vault.vaultTVL(), initialAssets * 3);
    }
}
