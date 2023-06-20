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
    ERC20 curveLPToken = ERC20(0xa138341185a9D0429B0021A11FB717B225e13e1F);

    BeefyStrategy strategy;

    uint256 initialAssets;

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
        assertEq(curveLPToken.balanceOf(address(strategy)), 0);
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

    function testDepositAndWithdrawFromVault() public virtual {
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

contract TestBeefyWithStrategyVault is TestBeefyStrategy {
    function setupBeefyStrategy() public override {
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

    function setUp() public override {
        vm.createSelectFork("polygon");
        StrategyVault sVault = new StrategyVault();

        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (governance, address(usdc), "BeefyVault", "BeefyVault"));

        vm.prank(governance);
        ERC1967Proxy proxy = new ERC1967Proxy(address(sVault), initData);

        vault = Vault(address(proxy));

        setupBeefyStrategy();
        initialAssets = 10_000 * (10 ** usdc.decimals());
        // // link strategy to vault.
        vm.prank(governance);
        StrategyVault(address(vault)).setStrategy(strategy);
        vm.prank(governance);
        strategy.setDefaultSlippageBps(50);
    }
    /// @dev override this as strategy directly sends assets to strategy

    function testDepositAndWithdrawFromVault() public override {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        /// @dev update tvl
        /// @dev only strategy can end epoch
        changePrank(address(strategy));
        StrategyVault(address(vault)).endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        changePrank(alice);
        vault.withdraw(initialAssets / 2, alice, alice);

        assertEq(usdc.balanceOf(alice), initialAssets / 2);
        assertEq(vault.vaultTVL(), strategy.totalLockedValue());
    }

    function testVaultUpgradeAndSwapStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(initialAssets, alice);

        assertEq(vault.vaultTVL(), initialAssets);

        /// @dev update tvl
        /// @dev only strategy can end epoch
        changePrank(address(strategy));
        StrategyVault(address(vault)).endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        // change prank to gov update vault

        changePrank(governance);
        vault.pause();

        StrategyVault(address(vault)).withdrawFromStrategy(vault.vaultTVL());

        // strategy tvl should be zero
        assertEq(strategy.totalLockedValue(), 0);
        assertEq(usdc.balanceOf(address(vault)), vault.vaultTVL());
        assertEq(usdc.balanceOf(address(strategy)), 0);
        uint256 oldTVL = vault.vaultTVL();
        address oldStrategy = address(strategy);
        // upgrade vault

        StrategyVault sVault = new StrategyVault();
        sVault.initialize(governance, address(usdc), "BeefyVault_v1", "BeefyVault_v1");

        StrategyVault oldImp = StrategyVault(address(vault));
        oldImp.upgradeTo(address(sVault));

        // strategy tvl should be zero
        assertEq(strategy.totalLockedValue(), 0);
        assertEq(usdc.balanceOf(address(vault)), vault.vaultTVL());
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertEq(oldTVL, vault.vaultTVL());

        // moving assets to strategy
        setupBeefyStrategy();
        StrategyVault(address(vault)).setStrategy(strategy);

        changePrank(address(this));

        strategy.setDefaultSlippageBps(500);

        changePrank(governance);

        StrategyVault(address(vault)).depositIntoStrategy(usdc.balanceOf(address(vault)));

        assertEq(usdc.balanceOf(address(vault)), 0);

        changePrank(address(strategy));
        StrategyVault(address(vault)).endEpoch();

        assertEq(vault.vaultTVL(), strategy.totalLockedValue());

        assertTrue(address(strategy) != oldStrategy);
        // usdc balance of strategy should be zero after invest
        assertEq(usdc.balanceOf(address(strategy)), 0);
    }

    /// @dev this test is done to test out live vault and strategy update.
    /// @dev may be discarded later
    function testVaultAndStrategyUpgradeWithDeployedVault() public {
        StrategyVault mainnetVault = StrategyVault(0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46);

        StrategyVault newVault = new StrategyVault();

        vm.startPrank(0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0); // gov
        mainnetVault.upgradeTo(address(newVault));

        BeefyStrategy vaultStrat = BeefyStrategy(address(mainnetVault.strategy()));
        uint256 tvl = vaultStrat.totalLockedValue();
        mainnetVault.pause();
        mainnetVault.withdrawFromStrategy(vaultStrat.totalLockedValue());

        assertEq(vaultStrat.totalLockedValue(), 0);
        assertEq(mainnetVault.vaultTVL(), tvl);

        vault = Vault(address(mainnetVault));

        setupBeefyStrategy();

        mainnetVault.setStrategy(strategy);
        strategy.setDefaultSlippageBps(500);

        mainnetVault.depositIntoStrategy(tvl);

        assertApproxEqRel(strategy.totalLockedValue(), tvl, 0.01e18);
    }
}
