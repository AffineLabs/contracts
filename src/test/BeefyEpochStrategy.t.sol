// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {BeefyEpochStrategy} from "src/strategies/BeefyEpochStrategy.sol";

import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console} from "forge-std/console.sol";

contract TestBeefyWithStrategyVault is TestPlus {
    StrategyVault vault;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    ICurvePool pool = ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F);
    I3CrvMetaPoolZap zapper = I3CrvMetaPoolZap(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939);
    IBeefyVault beefy = IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969);
    ERC20 curveLPToken = ERC20(0xa138341185a9D0429B0021A11FB717B225e13e1F);

    BeefyEpochStrategy strategy;

    uint256 initialAssets;
    uint256 defaultSlippageBps;

    function setupBeefyStrategy() public {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new BeefyEpochStrategy(
            vault, 
            pool,
            zapper,
            2, // assetIndex
            beefy,
            strategists
        );
    }

    function setUp() public {
        vm.createSelectFork("polygon", 44_367_000);
        StrategyVault sVault = new StrategyVault();

        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (governance, address(usdc), "BeefyVault", "BeefyVault"));

        vm.prank(governance);
        ERC1967Proxy proxy = new ERC1967Proxy(address(sVault), initData);

        vault = StrategyVault(address(proxy));

        setupBeefyStrategy();
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
        setupBeefyStrategy();
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

    /// @dev this test is done to test out live vault and strategy update.
    /// @dev may be discarded later
    function testStrategyUpgradeWithDeployedVault() public {
        StrategyVault mainnetVault = StrategyVault(0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46);

        vm.startPrank(0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0); // gov

        BeefyEpochStrategy vaultStrat = BeefyEpochStrategy(address(mainnetVault.strategy()));
        uint256 tvl = vaultStrat.totalLockedValue();
        mainnetVault.pause();

        // using strategy tvl to withdraw full assets
        mainnetVault.withdrawFromStrategy(vaultStrat.totalLockedValue());

        assertEq(vaultStrat.totalLockedValue(), 0);
        assertEq(mainnetVault.vaultTVL(), tvl);

        vault = mainnetVault;

        setupBeefyStrategy();

        mainnetVault.setStrategy(strategy);
        strategy.setDefaultSlippageBps(defaultSlippageBps);

        mainnetVault.depositIntoStrategy(tvl);

        assertApproxEqRel(strategy.totalLockedValue(), tvl, 0.01e18);

        assertEq(vault.vaultTVL(), tvl);

        vm.startPrank(address(this));

        strategy.endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        vm.startPrank(0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0);

        vault.unpause();
    }
}
