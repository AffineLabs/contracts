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
import {BeefyAeroStrategy} from "src/strategies/BeefyAeroStrategy.sol";

import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {IAeroRouter, IAeroPool} from "src/interfaces/IAerodrome.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console} from "forge-std/console.sol";

contract TestBeefyAeroStrategy is TestPlus {
    using FixedPointMathLib for uint256;

    Vault vault;
    ERC20 asset = ERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA); // usdbc
    IAeroRouter router = IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
    IBeefyVault beefy = IBeefyVault(0x8aeDd79BC918722d4948502b18deceaBeD60d044);
    ERC20 token1 = ERC20(0x9483ab65847A447e36d21af1CaB8C87e9712ff93); // wusdr

    BeefyAeroStrategy strategy;

    uint256 initialAssets;
    uint256 defaultSlippageBps;

    function setupBeefyStrategy() public virtual {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new BeefyAeroStrategy(
            vault, 
            beefy,
            router,
            token1,
            strategists
        );
    }

    function setUp() public virtual {
        vm.createSelectFork("base", 4_133_000);
        vault = vault = new Vault();
        vault.initialize(governance, address(asset), "DegenVault", "DegenVault");
        setupBeefyStrategy();
        initialAssets = 10_000 * (10 ** asset.decimals());
        // link strategy to vault.
        vm.prank(governance);
        vault.addStrategy(strategy, 10_000);
        vm.prank(governance);
        defaultSlippageBps = 50;
        strategy.setDefaultSlippageBps(defaultSlippageBps);
    }

    function testInvestIntoStrategy() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        assertEq(strategy.totalLockedValue(), initialAssets);

        vm.startPrank(address(this));

        strategy.investAssets(initialAssets, 50);

        console.log("TVL %s", strategy.totalLockedValue());
        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets, strategy.totalLockedValue(), 0.01e18);
        // should have less than 50 bps amount of asset
        // assertTrue(asset.balanceOf(address(strategy)) <= ((initialAssets*50)/10000));
        // assertEq(strategy.lpToken.balanceOf(address(strategy)), 0);
    }

    function testWithdrawFromStrategy() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets);

        assertApproxEqRel(asset.balanceOf(address(vault)), initialAssets, 0.01e18);

        assertEq(strategy.totalLockedValue(), 0);
    }

    function testWithdrawFromStrategyAfterInvestInLP() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets);

        assertApproxEqRel(asset.balanceOf(address(vault)), initialAssets, 0.01e18);

        assertEq(strategy.totalLockedValue(), 0);
    }

    function testDivestHalf() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets / 2);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets / 2, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(asset.balanceOf(address(vault)), initialAssets / 2, 0.01e18);
    }

    function testDivestHalfAfterInvestInLP() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        vm.startPrank(address(vault));
        strategy.divest(initialAssets / 2);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets / 2, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(asset.balanceOf(address(vault)), initialAssets / 2, 0.01e18);
    }

    function testDivestByStrategist() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        assertEq(asset.balanceOf(address(strategy)), 0);

        strategy.divestAssets(initialAssets, defaultSlippageBps);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(asset.balanceOf(address(strategy)), initialAssets, 0.01e18);
    }

    function testInvestWithExistingUSDR() public {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);

        asset.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        vm.startPrank(address(this));
        strategy.investAssets(initialAssets, defaultSlippageBps);

        assertEq(asset.balanceOf(address(strategy)), 0);

        uint256 remainingUSDRAmount = token1.balanceOf(address(strategy));
        uint256 USDREqassetAmount = remainingUSDRAmount.mulDivDown(10 ** asset.decimals(), 10 ** token1.decimals());

        console.log(
            "01 Rem asset %s, USDR %s, TVL %s",
            asset.balanceOf(address(strategy)),
            token1.balanceOf(address(strategy)),
            strategy.totalLockedValue()
        );

        deal(address(asset), alice, USDREqassetAmount);
        vm.startPrank(alice);

        strategy.invest(USDREqassetAmount);

        // total tvl
        uint256 totalTVL = initialAssets + USDREqassetAmount;
        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.005e18);

        vm.startPrank(address(this));
        strategy.investAssets(USDREqassetAmount / 2, defaultSlippageBps);

        console.log(
            "02 Rem asset %s, USDR %s, TVL %s",
            asset.balanceOf(address(strategy)),
            token1.balanceOf(address(strategy)),
            strategy.totalLockedValue()
        );

        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.005e18);

        strategy.investAssets(asset.balanceOf(address(strategy)), defaultSlippageBps);
        console.log(
            "03 Rem asset %s, USDR %s, TVL %s",
            asset.balanceOf(address(strategy)),
            token1.balanceOf(address(strategy)),
            strategy.totalLockedValue()
        );
        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.005e18);

        strategy.divestAssets(initialAssets, defaultSlippageBps);

        // // tvl should be in range of BPS
        assertApproxEqRel(totalTVL, strategy.totalLockedValue(), 0.005e18);

        assertApproxEqRel(asset.balanceOf(address(strategy)), initialAssets, 0.01e18);
        console.log(
            "03 Rem asset %s, USDR %s, TVL %s",
            asset.balanceOf(address(strategy)),
            token1.balanceOf(address(strategy)),
            strategy.totalLockedValue()
        );
    }

    function testDepositAndWithdrawFromVault() public virtual {
        deal(address(asset), alice, initialAssets);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        vm.startPrank(governance);

        vault.depositIntoStrategies(asset.balanceOf(address(vault)));

        // update block timestamp to harvest

        vm.warp(block.timestamp + 3 days);

        // harvest
        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = strategy;
        vault.harvest(strategies);

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        vm.startPrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);

        assertEq(asset.balanceOf(alice), initialAssets / 2);
        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        vm.startPrank(address(this));

        strategy.investAssets(initialAssets / 2, defaultSlippageBps);

        assertEq(asset.balanceOf(address(strategy)), 0);
    }
}
