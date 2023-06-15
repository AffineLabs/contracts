// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {Vault} from "src/vaults/Vault.sol";
import {BeefyStrategy} from "src/strategies/BeefyStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";

import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {DeployLib} from "script/ConvexStrategy.s.sol";

import {console} from "forge-std/console.sol";

contract TestBeefyStrategy is TestPlus {
    Vault vault;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    BeefyStrategy strategy;

    uint256 initialAssets;

    function setupBeefyStrategy() public {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new BeefyStrategy(
            vault, 
            ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F),
            I3CrvMetaPoolZap(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939),
            2, // assetIndex
            IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969),
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
    }

    function testInit() public {
        assertTrue(true);
    }

    function testTransferAssetsVaultToStrategy() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(vault), type(uint256).max);

        vault.deposit(initialAssets, alice);

        changePrank(governance);
        vault.depositIntoStrategies(usdc.balanceOf(address(vault)));

        assertTrue(true);
        vm.stopPrank();
    }

    function testDivestFull() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        changePrank(address(vault));
        strategy.divest(initialAssets);

        console.log("strategy tvl %s", strategy.totalLockedValue());
        console.log("usdc balance of strategy %s", usdc.balanceOf(address(strategy)));
        console.log(
            "beefy balance %s", IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969).balanceOf(address(strategy))
        );
        console.log(
            "lp token balance %s", ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F).balanceOf(address(strategy))
        );
        console.log("alice usdc balance", usdc.balanceOf(alice));
        assertTrue(true);
        vm.stopPrank();
    }

    function testDivestHalf() public {
        deal(address(usdc), alice, initialAssets);
        vm.startPrank(alice);

        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(initialAssets);

        changePrank(address(vault));
        strategy.divest(initialAssets / 2);

        console.log("strategy tvl %s", strategy.totalLockedValue());
        console.log("usdc balance of strategy %s", usdc.balanceOf(address(strategy)));
        console.log(
            "beefy balance %s", IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969).balanceOf(address(strategy))
        );
        console.log(
            "lp token balance %s", ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F).balanceOf(address(strategy))
        );
        console.log("alice usdc balance", usdc.balanceOf(alice));
        assertTrue(true);
        vm.stopPrank();
    }
}
