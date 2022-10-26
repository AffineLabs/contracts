// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {CurveStrategy} from "../ethereum/CurveStrategy.sol";
import {I3CrvMetaPoolZap, ILiquidityGauge, ICurvePool, IMinter} from "../interfaces/curve.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract CurveStratTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    L1Vault vault;
    CurveStrategy strategy;
    ERC20 metaPool;
    ILiquidityGauge gauge;
    IMinter minter = IMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);

    function setUp() public {
        vm.createSelectFork("ethereum", 15_774_176);
        vault = deployL1Vault();

        // make vault token equal to the L1 usdc address
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(address(usdc))))
        );

        strategy = new CurveStrategy(vault, 
                         ERC20(0x5a6A4D54456819380173272A5E8E9B9904BdF41B),
                         I3CrvMetaPoolZap(0xA79828DF1850E8a3A3064576f380D90aECDD3359), 
                         2,
                         ILiquidityGauge(0xd8b712d29381748dB89c36BCa0138d7c75866ddF)
                         );

        // To be able to call functions restricted to strategist role.
        vm.startPrank(vault.governance());
        vault.grantRole(vault.STRATEGIST(), address(this));
        vm.stopPrank();

        metaPool = strategy.metaPool();
        gauge = strategy.gauge();
    }

    function _invest(uint256 amount) internal {
        // get some usdc
        // invest in the vault
        deal(address(usdc), address(this), amount);
        usdc.approve(address(strategy), type(uint256).max);

        strategy.invest(amount);
        strategy.deposit(amount, 0);
    }

    function testCanMintLpTokens() public {
        _invest(1e6);

        assertGt(strategy.gauge().balanceOf(address(strategy)), 0);
        emit log_named_uint("strat tvl: ", strategy.totalLockedValue());

        assertApproxEqRel(strategy.totalLockedValue(), 1e6, 0.02e18);

        // we get rewards if time passes
        vm.warp(block.timestamp + 5 days);
        uint256 crvRewards = strategy.gauge().claimable_tokens(address(strategy));
        emit log_named_uint("crv rewards: ", crvRewards);
        assertTrue(crvRewards > 0);
    }

    function testCanSlip() public {
        deal(address(usdc), address(strategy), 100e6);

        vm.expectRevert();
        strategy.deposit(100e6, type(uint256).max);

        strategy.deposit(100e6, 0);

        deal(address(strategy.crv()), address(strategy), 1e18 * 100);
        vm.expectRevert();
        strategy.claimRewards(type(uint256).max);

        strategy.claimRewards(0);
    }

    function testCanDivest() public {
        // One lp token is worth more than a dollar
        deal(address(metaPool), address(strategy), 1e18);

        vm.prank(address(vault));
        uint256 amountDivested = strategy.divest(1e6);

        assertTrue(amountDivested == 1e6);
        assertTrue(usdc.balanceOf(address(vault)) == 1e6);
    }

    function testCanDivestFully() public {
        // If we try to withdraw more money than actually exists in the vault
        // We end up approximately no lp tokens and a bunch of usdc
        deal(address(metaPool), address(strategy), 2e18);
        deal(address(gauge), address(strategy), 1e18);

        strategy.withdrawAssets(5 * 1e6); // lp token is worth a bit more than a dollar

        assertApproxEqRel(strategy.totalLockedValue(), 3e6, 0.01e18);
        assertApproxEqAbs(metaPool.balanceOf(address(strategy)), 0, 0.01e18);
        assertApproxEqAbs(gauge.balanceOf(address(strategy)), 0, 0.01e18);
    }

    function testWithdrawFuzz(uint64 lpTokens, uint64 gaugeTokens, uint32 assetsToDivest) public {
        deal(address(metaPool), address(strategy), lpTokens);
        deal(address(gauge), address(strategy), gaugeTokens);

        strategy.withdrawAssets(assetsToDivest);
    }

    function testTVLFuzz(uint64 lpTokens, uint64 gaugeTokens) public {
        // Each token is roughly $1, and tvl function should reflect that
        deal(address(metaPool), address(strategy), lpTokens);
        deal(address(gauge), address(strategy), gaugeTokens);

        uint256 tvl = strategy.totalLockedValue();
        if (tvl > 100) {
            // For small numbers the percentage difference can be greater than 1 (e.g. 74 vs 75 are more than 1% diff)
            assertApproxEqRel(tvl, (uint256(gaugeTokens) + lpTokens) / 1e12, 0.05e18);
        }
    }

    function testCanClaimRewards() public {
        _invest(1e6 * 1e6);
        vm.warp(block.timestamp + 365 days);

        uint256 oldTvl = strategy.totalLockedValue();
        strategy.claimRewards(0);
        assertGt(strategy.totalLockedValue(), oldTvl);
    }

    function testCanSellRewards() public {
        deal(address(strategy.crv()), address(strategy), 1e18 * 100);

        strategy.claimRewards(0);

        // We have usdc
        assertTrue(usdc.balanceOf(address(strategy)) > 0);
        // We sold all of our crv
        assertEq(strategy.crv().balanceOf(address(strategy)), 0);
    }
}
