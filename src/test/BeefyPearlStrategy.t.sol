// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {Vault} from "src/vaults/Vault.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {BeefyPearlStrategy} from "src/strategies/BeefyPearlStrategy.sol";
import {BeefyEpochStrategy} from "src/strategies/BeefyEpochStrategy.sol";

import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {IRouter, IPair} from "src/interfaces/IPearl.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console2} from "forge-std/console2.sol";

contract TestBeefyPearlStrategy is TestPlus {
    using FixedPointMathLib for uint256;

    Vault vault;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IRouter router = IRouter(0xcC25C0FD84737F44a7d38649b69491BBf0c7f083);
    IBeefyVault beefy = IBeefyVault(0xD74B5df80347cE9c81b91864DF6a50FfAfE44aa5);
    ERC20 token1 = ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);

    BeefyPearlStrategy strategy;

    uint256 initialAssets;
    uint256 defaultSlippageBps;

    function setupBeefyStrategy() public virtual {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new BeefyPearlStrategy(
            vault, 
            beefy,
            router,
            token1,
            strategists
        );
    }

    function setUp() public virtual {
        vm.createSelectFork("polygon", 46_643_471);
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

        console2.log("TVL %s", strategy.totalLockedValue());
        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets, strategy.totalLockedValue(), 0.01e18);
        // should have less than 50 bps amount of usdc
        // assertTrue(usdc.balanceOf(address(strategy)) <= ((initialAssets*50)/10000));
        // assertEq(strategy.lpToken.balanceOf(address(strategy)), 0);
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

    function testInvestWithExistingUSDR() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        assertEq(usdc.balanceOf(address(strategy)), 0);

        uint256 remainingUSDRAmount = token1.balanceOf(address(strategy));
        uint256 USDREqUSDCAmount = remainingUSDRAmount.mulDivDown(10 ** usdc.decimals(), 10 ** token1.decimals());

        deal(address(usdc), alice, USDREqUSDCAmount);
        vm.startPrank(alice);

        strategy.invest(USDREqUSDCAmount);

        // total tvl
        uint256 totalTVL = initialAssets + USDREqUSDCAmount;
        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.001e18);

        vm.startPrank(address(this));
        strategy.investAssets(USDREqUSDCAmount / 2, defaultSlippageBps);

        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.001e18);

        strategy.investAssets(usdc.balanceOf(address(strategy)), defaultSlippageBps);
        console2.log(
            "01 Rem USDC %s, USDR %s, TVL %s",
            usdc.balanceOf(address(strategy)),
            token1.balanceOf(address(strategy)),
            strategy.totalLockedValue()
        );
        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.001e18);

        strategy.divestAssets(initialAssets, defaultSlippageBps);

        // // tvl should be in range of BPS
        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.001e18);

        assertApproxEqRel(usdc.balanceOf(address(strategy)), initialAssets, 0.01e18);
        console2.log(
            "02 Rem USDC %s, USDR %s, TVL %s",
            usdc.balanceOf(address(strategy)),
            token1.balanceOf(address(strategy)),
            strategy.totalLockedValue()
        );
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
