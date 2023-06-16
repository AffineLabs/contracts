// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {Vault} from "src/vaults/Vault.sol";
import {BeefyStrategy} from "src/strategies/BeefyStrategy.sol";

import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console} from "forge-std/console.sol";

contract TestBeefyStrategy is TestPlus {
    Vault vault;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    ICurvePool pool = ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F);
    I3CrvMetaPoolZap zapper = I3CrvMetaPoolZap(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939);
    IBeefyVault beefy = IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969);

    BeefyStrategy strategy;

    uint256 initialAssets;

    function setupBeefyStrategy() public {
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

    function setUp() public {
        vm.createSelectFork("polygon");
        vault = vault = new Vault();
        vault.initialize(governance, address(usdc), "BeefyVault", "BeefyVault");
        setupBeefyStrategy();
        initialAssets = 10_000 * (10 ** usdc.decimals());
        // link strategy to vault.
        vm.prank(governance);
        vault.addStrategy(strategy, 10_000);
        vm.prank(governance);
        strategy.setDefaultSlippageBps(50);
    }

    function testInvestIntoStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets, strategy.totalLockedValue(), 0.01e18);
        // should use all usdc
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertEq(pool.balanceOf(address(strategy)), 0);
    }

    function testWithdrawFromStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        changePrank(address(vault));
        strategy.divest(initialAssets);

        assertApproxEqRel(usdc.balanceOf(address(vault)), initialAssets, 0.01e18);

        assertEq(strategy.totalLockedValue(), 0);
    }

    function testDivestHalf() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        changePrank(address(vault));
        strategy.divest(initialAssets / 2);

        // tvl should be in range of BPS
        assertApproxEqRel(initialAssets / 2, strategy.totalLockedValue(), 0.01e18);

        assertApproxEqRel(usdc.balanceOf(address(vault)), initialAssets / 2, 0.01e18);
    }

    function testDepositAndWithdrawFromVault() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        changePrank(governance);
        vault.depositIntoStrategies(usdc.balanceOf(address(vault)));

        assertEq(vault.vaultTVL(), initialAssets);
        // update block timestamp to harvest

        vm.warp(block.timestamp + 3 days);

        // harvest
        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = strategy;
        vault.harvest(strategies);

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        changePrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);

        assertEq(usdc.balanceOf(alice), initialAssets / 2);
        assertEq(vault.vaultTVL(), strategy.totalLockedValue());
    }
}
