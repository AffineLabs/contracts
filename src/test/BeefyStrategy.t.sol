// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {Vault} from "src/vaults/Vault.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {BeefyStrategy} from "src/strategies/BeefyStrategy.sol";
import {BeefyEpochStrategy} from "src/strategies/BeefyEpochStrategy.sol";

import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console2} from "forge-std/console2.sol";

contract TestBeefyStrategy is TestPlus {
    Vault vault;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    ICurvePool pool = ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F);
    I3CrvMetaPoolZap zapper = I3CrvMetaPoolZap(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939);
    IBeefyVault beefy = IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969);
    ERC20 curveLPToken = ERC20(0xa138341185a9D0429B0021A11FB717B225e13e1F);

    BeefyStrategy strategy;

    uint256 initialAssets;
    uint256 defaultSlippageBps;

    function setupBeefyStrategy() public virtual {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new BeefyStrategy(
            vault, 
            pool,
            zapper,
            2, // assetIndex
            beefy,
            strategists
        );
    }

    function setUp() public virtual {
        vm.createSelectFork("polygon", 44_367_000);
        vault = vault = new Vault();
        vault.initialize(governance, address(usdc), "BeefyVault", "BeefyVault");
        setupBeefyStrategy();
        initialAssets = 10_000 * (10 ** usdc.decimals());
        // link strategy to vault.
        vm.prank(governance);
        vault.addStrategy(strategy, 10_000);
        vm.prank(governance);
        defaultSlippageBps = 50;
        strategy.setDefaultSlippageBps(defaultSlippageBps);
    }

    function testInvestIntoStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        assertEq(strategy.totalLockedValue(), initialAssets);

        vm.startPrank(address(this));

        strategy.investAssets(initialAssets, 50);
        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets, strategy.totalLockedValue(), 0.01e18);
        // should use all usdc
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertEq(curveLPToken.balanceOf(address(strategy)), 0);
    }

    function testWithdrawFromStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets);

        assertApproxEqRel(usdc.balanceOf(address(vault)), initialAssets, 0.01e18);

        assertEq(strategy.totalLockedValue(), 0);
    }

    function testWithdrawFromStrategyAfterInvestInLP() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets);

        assertApproxEqRel(usdc.balanceOf(address(vault)), initialAssets, 0.01e18);

        assertEq(strategy.totalLockedValue(), 0);
    }

    function testDivestHalf() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets / 2);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets / 2, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(usdc.balanceOf(address(vault)), initialAssets / 2, 0.01e18);
    }

    function testDivestHalfAfterInvestInLP() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets / 2);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets / 2, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(usdc.balanceOf(address(vault)), initialAssets / 2, 0.01e18);
    }

    function testDivestByStrategist() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        assertEq(usdc.balanceOf(address(strategy)), 0);

        strategy.divestAssets(initialAssets, defaultSlippageBps);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(usdc.balanceOf(address(strategy)), initialAssets, 0.01e18);
    }

    function testDepositAndWithdrawFromVault() public virtual {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        vm.startPrank(governance);

        vault.depositIntoStrategies(usdc.balanceOf(address(vault)));

        // update block timestamp to harvest

        vm.warp(block.timestamp + 3 days);

        // harvest
        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = strategy;
        vault.harvest(strategies);

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        vm.startPrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);

        assertEq(usdc.balanceOf(alice), initialAssets / 2);
        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        vm.startPrank(address(this));

        strategy.investAssets(initialAssets / 2, defaultSlippageBps);

        assertEq(usdc.balanceOf(address(strategy)), 0);
    }
}
