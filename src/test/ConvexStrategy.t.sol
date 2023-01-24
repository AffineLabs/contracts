// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {ConvexStrategy} from "../ethereum/ConvexStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "../interfaces/curve.sol";
import {IConvexBooster} from "../interfaces/convex.sol";

import {DeployLib} from "../../script/ConvexStrategy.s.sol";

import "forge-std/console.sol";

/// @notice Test convex FRAX-USDC strategy
contract ConvexStratTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    L1Vault vault;
    ConvexStrategy strategy;
    ERC20 crv;
    ERC20 cvx;

    function _deployStrategy() internal virtual {
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);

        strategy = new ConvexStrategy(
            {_vault: vault, 
            _assetIndex: 1,
            _isMetaPool: false, 
            _curvePool: ICurvePool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2),
            _zapper: I3CrvMetaPoolZap(address(0)),
            _convexPid: 100,
            strategists: strategists
            });
    }

    function setUp() public {
        vm.createSelectFork("ethereum", 15_624_364);
        vault = deployL1Vault();

        // Make vault asset equal to usdc
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(address(usdc))))
        );

        _deployStrategy();

        // To be able to call functions restricted to strategist role.
        vm.startPrank(vault.governance());
        strategy.grantRole(strategy.STRATEGIST_ROLE(), address(this));
        vm.stopPrank();

        crv = strategy.CRV();
        cvx = strategy.CVX();
    }

    /// @notice Test depositing into strategy works.
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

    /// @notice Test slippage doesn't incure error while claiming/selling rewards.
    function testCanSlip() public {
        deal(address(usdc), address(strategy), 1e12);
        deal(address(crv), address(strategy), 10e18);
        deal(address(cvx), address(strategy), 10e18);

        vm.expectRevert();
        strategy.deposit(1e12, type(uint256).max);

        strategy.deposit(1e12, 0);

        vm.expectRevert();
        strategy.claimAndSellRewards(type(uint256).max, type(uint256).max);

        strategy.claimAndSellRewards(0, 0);
    }

    /// @notice Test divesting from convex strategy works.
    function testCanDivest() public {
        deal(address(usdc), address(this), 2e6);
        usdc.approve(address(strategy), type(uint256).max);
        strategy.invest(2e6);
        strategy.deposit(2e6, 0);

        vm.prank(address(vault));
        strategy.divest(1e6);
        emit log_named_uint("vault usdc: ", usdc.balanceOf(address(vault)));
        assertTrue(usdc.balanceOf(address(vault)) == 1e6);
    }

    /// @notice Fuzz test to make sure we are able to withdraw from convex strategy in random scenarios.
    function testWithdrawFuzz(uint64 lpTokens, uint64 cvxLpTokens, uint32 assetsToDivest) public {
        deal(address(strategy.curveLpToken()), address(strategy), lpTokens);
        deal(address(strategy.cvxRewarder()), address(strategy), cvxLpTokens);

        strategy.withdrawAssets(assetsToDivest);
    }

    /// @notice Test claiming rewards.
    function testRewards() public {
        deal(address(usdc), address(strategy), 1e12);
        strategy.deposit(1e12, 0);
        vm.warp(block.timestamp + 365 days);

        strategy.claimRewards();

        assertGt(strategy.CVX().balanceOf(address(strategy)), 0);
        assertGt(strategy.CRV().balanceOf(address(strategy)), 0);
    }

    /// @notice Test selling reward tokens.
    function testCanSellRewards() public {
        deal(address(strategy.CRV()), address(strategy), strategy.MIN_TOKEN_AMT() * 10);
        deal(address(strategy.CVX()), address(strategy), strategy.MIN_TOKEN_AMT() * 10);

        strategy.claimAndSellRewards(0, 0);

        // We have usdc
        assertTrue(usdc.balanceOf(address(strategy)) > 0);
        // We sold all of our crv
        assertEq(strategy.CRV().balanceOf(address(strategy)), 0);
        assertEq(strategy.CVX().balanceOf(address(strategy)), 0);
    }

    /// @notice Fuzz test of tvl function.
    function testTVLFuzz(uint64 lpTokens, uint64 cvxLpTokens) public {
        deal(address(strategy.curveLpToken()), address(strategy), lpTokens);
        deal(address(strategy.cvxRewarder()), address(strategy), cvxLpTokens);

        uint256 tvl = strategy.totalLockedValue();
        if (tvl < 100) return;
        assertApproxEqRel(tvl, (uint256(lpTokens) + cvxLpTokens) / 1e12, 0.02e18);
    }
}

contract ConvexStratMIMTest is ConvexStratTest {
    // Make this public and run it in order to get convex pool id for a given lp token
    function testBooster() internal {
        IConvexBooster booster = strategy.convexBooster();
        uint256 length = booster.poolLength();
        console.log("length: ", length);

        for (uint256 i = 0; i < length; ++i) {
            IConvexBooster.PoolInfo memory poolInfo = booster.poolInfo(i);
            if (poolInfo.lptoken == 0x5a6A4D54456819380173272A5E8E9B9904BdF41B) {
                console.log("pid: ", i);
            }
        }
    }

    function _deployStrategy() internal override {
        strategy = DeployLib.deployMim3Crv(vault);
    }
}
