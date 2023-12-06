// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";

import {VaultV2} from "src/vaults/VaultV2.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

import {SDaiStrategy} from "src/strategies/SDaiStrategy.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";

import {console2} from "forge-std/console2.sol";

contract SDaiStrategyTest is TestPlus {
    VaultV2 vault;
    SDaiStrategy strategy;
    ERC20 asset = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint256 init_assets;

    function _initVault() internal {
        vault = new VaultV2();
        vault.initialize(governance, address(asset), "TV", "TV");
    }

    function setUp() public {
        vm.createSelectFork("ethereum", 18_728_000);
        _initVault();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);

        strategy = new SDaiStrategy(AffineVault(address(vault)), strategists);

        vm.startPrank(governance);

        vault.addStrategy(strategy, 10_000);
        init_assets = 100 * 10 ** asset.decimals();
    }

    function _depositToVault() internal {
        deal(address(asset), address(alice), init_assets);

        vm.startPrank(alice);

        asset.approve(address(vault), init_assets);
        vault.deposit(init_assets, alice);
        assertEq(vault.vaultTVL(), init_assets);
    }

    function _depositIntoStrategy() internal {
        _depositToVault();

        // deposit into strategy
        vm.startPrank(governance); // strategist

        vault.depositIntoStrategies(init_assets);
    }

    function testInvest() public {
        _depositToVault();

        // deposit into strategy
        vm.startPrank(governance); // strategist

        vault.depositIntoStrategies(init_assets);
        assertApproxEqRel(strategy.totalLockedValue(), init_assets, 0.001e18);
    }

    function testDivest() public {
        _depositIntoStrategy();

        vm.startPrank(address(vault));
        strategy.divest(strategy.totalLockedValue());

        assertEq(strategy.totalLockedValue(), 0);

        vm.startPrank(governance);
        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = BaseStrategy(address(strategy));

        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        vault.harvest(strategies);
        assertApproxEqRel(vault.vaultTVL(), init_assets, 0.001e18);
    }

    function testWithdraw() public {
        _depositIntoStrategy();

        vm.startPrank(alice);

        // withdraw for alice
        vault.withdraw(init_assets, alice, alice);

        assertEq(strategy.totalLockedValue(), 0);
        assertEq(vault.vaultTVL(), 0);
        assertApproxEqRel(asset.balanceOf(alice), init_assets, 0.001e18);
    }
}
