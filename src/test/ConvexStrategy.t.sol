// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {ConvexStrategy} from "../ethereum/ConvexStrategy.sol";
import {ICurvePool} from "../interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "../interfaces/convex.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ConvexStratTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    L1Vault vault;
    ConvexStrategy strategy;

    function setUp() public {
        vm.createSelectFork("ethereum", 15_624_364);
        vault = deployL1Vault();

        // make vault token equal to the L1 usdc address
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(address(usdc))))
        );
        strategy = new ConvexStrategy(
            vault, 
            ICurvePool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2),
            100,
            IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31));
    }

    function testCanDeposit() public {
        // get some usdc
        // invest in the vault
        deal(address(usdc), address(this), 1e6);
        usdc.approve(address(strategy), type(uint256).max);
        strategy.invest(1e6);
        // Strategy owner actually mints lp tokens
        strategy.deposit(1e6, 0);

        // This is not a rewards token balance. This just tells us how much cvxcrvFRAX we've deposited
        // into the rewards contract
        uint256 rewardTokenBalance = strategy.cvxRewarder().balanceOf(address(strategy));
        assertGt(rewardTokenBalance, 0);

        uint256 tvl = strategy.totalLockedValue();
        emit log_named_uint("strat tvl: ", tvl);
        assertApproxEqRel(tvl, 1e6, 1e18);
    }

    function testCanDivest() public {
        deal(address(usdc), address(this), 2e6);
        usdc.approve(address(strategy), type(uint256).max);
        strategy.invest(2e6);
        strategy.deposit(2e6, 0);

        vm.prank(address(vault));
        strategy.divest(1e6);
        emit log_named_uint("vault usdc: ", usdc.balanceOf(address(vault)));
        assert(usdc.balanceOf(address(vault)) == 1e6);
    }

    function testRewards() public {
        deal(address(usdc), address(strategy), 1e12);
        strategy.deposit(1e12, 0);

        uint256 prevTVL = strategy.totalLockedValue();
        vm.warp(block.timestamp + 365 days);

        strategy.claimRewards();

        assertGt(strategy.cvx().balanceOf(address(strategy)), 0);
        assertGt(strategy.crv().balanceOf(address(strategy)), 0);
    }

    function testCanSellRewards() public {
        deal(address(strategy.crv()), address(strategy), strategy.MIN_TOKEN_AMT() * 10);
        deal(address(strategy.cvx()), address(strategy), strategy.MIN_TOKEN_AMT() * 10);

        strategy.claimAndSellRewards(0, 0);

        // We have usdc
        assertTrue(usdc.balanceOf(address(strategy)) > 0);
        // We sold all of our crv
        assertEq(strategy.crv().balanceOf(address(strategy)), 0);
        assertEq(strategy.cvx().balanceOf(address(strategy)), 0);
    }

    function testTVLFuzz(uint64 lpTokens, uint64 cvxLpTokens) public {
        deal(address(strategy.curveLpToken()), address(strategy), lpTokens);
        deal(address(strategy.cvxRewarder()), address(strategy), cvxLpTokens);

        uint256 tvl = strategy.totalLockedValue();
        assertApproxEqRel(tvl, (uint256(lpTokens) + cvxLpTokens) / 1e12, 0.02e18);
    }

    function testCanSlip() public {
        deal(address(usdc), address(strategy), 1e12);

        vm.expectRevert();
        strategy.deposit(1e12, type(uint256).max);

        strategy.deposit(1e12, 0);

        vm.expectRevert();
        // If we set minAssetsFromLp too high, we won't be able to withdraw
        strategy.withdrawAssets(type(uint256).max, type(uint256).max);

        strategy.withdrawAssets(type(uint256).max, 0);
    }
}
