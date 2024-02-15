// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {BeefyEpochStrategy} from "src/strategies/BeefyEpochStrategy.sol";
import {BeefyPearlEpochStrategy} from "src/strategies/BeefyPearlStrategy.sol";

import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";
import {IRouter, IPair} from "src/interfaces/IPearl.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console2} from "forge-std/console2.sol";

contract TestBeefyPearlWithStrategyVault is TestPlus {
    StrategyVault vault;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IRouter router = IRouter(0xcC25C0FD84737F44a7d38649b69491BBf0c7f083);
    IBeefyVault beefy = IBeefyVault(0xD74B5df80347cE9c81b91864DF6a50FfAfE44aa5);
    ERC20 token1 = ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);

    BeefyPearlEpochStrategy strategy;

    uint256 initialAssets;
    uint256 defaultSlippageBps;

    function setupBeefyPearlEpochStrategy() public {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new BeefyPearlEpochStrategy(vault, beefy, router, token1, strategists);
    }

    function setUp() public {
        vm.createSelectFork("polygon", 46_643_471);
        StrategyVault sVault = new StrategyVault();

        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (governance, address(usdc), "BeefyVault", "BeefyVault"));

        vm.prank(governance);
        ERC1967Proxy proxy = new ERC1967Proxy(address(sVault), initData);

        vault = StrategyVault(address(proxy));

        setupBeefyPearlEpochStrategy();
        initialAssets = 10_000 * (10 ** usdc.decimals());
        // // link strategy to vault.
        vm.prank(governance);
        StrategyVault(address(vault)).setStrategy(strategy);
        vm.prank(governance);
        defaultSlippageBps = 50;
        strategy.setDefaultSlippageBps(defaultSlippageBps);
    }

    function testDepositAndWithdrawFromVault() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        vm.startPrank(address(this));
        strategy.endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        vm.startPrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);

        assertEq(usdc.balanceOf(alice), initialAssets / 2);
        assertEq(vault.vaultTVL(), strategy.totalLockedValue());
    }

    function testDepositInvestWithdrawFromVault() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        vm.startPrank(address(this));
        strategy.endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        strategy.investAssets(strategy.totalLockedValue(), 50);

        vm.startPrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);

        assertEq(usdc.balanceOf(alice), initialAssets / 2);
        assertEq(vault.vaultTVL(), strategy.totalLockedValue());
        // remaining vault tvl and strategy tvl should be half

        assertApproxEqRel(strategy.totalLockedValue(), initialAssets / 2, 0.01e18);
    }

    function testReplaceStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        vm.startPrank(address(this));
        strategy.endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        // change prank to gov update vault

        vm.startPrank(governance);
        vault.pause();

        vault.withdrawFromStrategy(vault.vaultTVL());

        // strategy tvl should be zero
        assertEq(strategy.totalLockedValue(), 0);
        assertEq(usdc.balanceOf(address(vault)), vault.vaultTVL());
        assertEq(usdc.balanceOf(address(strategy)), 0);
        uint256 oldTVL = vault.vaultTVL();

        address oldStrategy = address(strategy);

        // moving assets to strategy
        setupBeefyPearlEpochStrategy();
        vault.setStrategy(strategy);

        vm.startPrank(address(this));

        strategy.setDefaultSlippageBps(defaultSlippageBps);

        vm.startPrank(governance);

        vault.depositIntoStrategy(vault.vaultTVL());

        assertEq(usdc.balanceOf(address(vault)), 0);

        assertEq(vault.vaultTVL(), oldTVL);

        vm.startPrank(address(this));
        strategy.endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        assertTrue(address(strategy) != oldStrategy);
        // usdc balance of strategy should be zero after invest

        strategy.investAssets(usdc.balanceOf(address(strategy)), defaultSlippageBps);

        assertEq(usdc.balanceOf(address(strategy)), 0);

        vm.startPrank(governance);
        vault.unpause();

        //trying to withdraw
        vm.startPrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);
        assertApproxEqRel(usdc.balanceOf(alice), initialAssets / 2, 0.01e18);
    }
}
