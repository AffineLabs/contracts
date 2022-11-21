// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "forge-std/Components.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {ILendingPoolAddressesProviderRegistry} from "../interfaces/aave.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {DeltaNeutralLpV3} from "../polygon/DeltaNeutralLpV3.sol";

contract DeltaNeutralV3Test is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
    DeltaNeutralLpV3 strategy;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    ERC20 asset;
    ERC20 borrowAsset;
    int24 tickLow;
    int24 tickHigh;
    uint256 slippageBps = 500;

    function setUp() public {
        vm.createSelectFork("polygon", 31_824_532);
        vault = deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        // weth/usdc pool
        IUniswapV3Pool pool = IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608);
        (, int24 tick,,,,,) = pool.slot0();
        int24 tSpace = pool.tickSpacing();
        int24 usableTick = (tick / tSpace) * tSpace;
        tickLow = usableTick - 20 * tSpace;
        tickHigh = usableTick + 20 * tSpace;

        strategy = new DeltaNeutralLpV3(
        vault,
        0.05e18,
        ILendingPoolAddressesProviderRegistry(0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19),
        ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619), // weth
        AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945), // eth/usd price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        pool
        );

        vm.startPrank(governance);
        vault.addStrategy(strategy, 5000);
        strategy.grantRole(strategy.STRATEGIST_ROLE(), address(this));
        vm.stopPrank();

        asset = usdc;
        borrowAsset = strategy.borrowAsset();
    }

    function testCreatePosition() public {
        uint256 startAssets = 1000e6;
        deal(address(usdc), address(strategy), startAssets);

        strategy.startPosition(tickLow, tickHigh, slippageBps);
        assertFalse(strategy.canStartNewPos());

        // I have the right amount of aUSDC
        assertEq(strategy.aToken().balanceOf(address(strategy)), startAssets * 4 / 7);

        // I put the correct amount of money into uniswap pool
        uint256 assetsLP = strategy.valueOfLpPosition();
        uint256 assetsInAAve = strategy.aToken().balanceOf(address(strategy)) * 3 / 4;
        emit log_named_uint("assetsLP: ", assetsLP);
        emit log_named_uint("assetsInAAve: ", assetsInAAve);
        assertApproxEqRel(assetsLP, assetsInAAve * 2, 0.015e18);
    }

    function testEndPosition() public {
        deal(address(asset), address(strategy), 1000e6);
        strategy.startPosition(tickLow, tickHigh, slippageBps);

        vm.expectRevert();
        vm.prank(alice);
        strategy.endPosition(slippageBps);

        strategy.endPosition(slippageBps);

        assertTrue(strategy.canStartNewPos());

        assertApproxEqRel(asset.balanceOf(address(strategy)), 1000e6, 0.02e18);
        assertEq(borrowAsset.balanceOf(address(strategy)), 0);
        assertEq(strategy.lpLiquidity(), 0);
    }

    function testTVL() public {
        assertEq(strategy.totalLockedValue(), 0);
        deal(address(asset), address(strategy), 1000e6);
        strategy.startPosition(tickLow, tickHigh, slippageBps);

        assertApproxEqRel(strategy.totalLockedValue(), 1000e6, 0.02e18);
    }

    function testDivest() public {
        // If there's no position active, we just send our current balance
        deal(address(asset), address(strategy), 1);
        vm.prank(address(vault));
        strategy.divest(1);
        assertEq(asset.balanceOf(address(vault)), 1);

        deal(address(asset), address(strategy), 1000e6);
        strategy.startPosition(tickLow, tickHigh, slippageBps);

        // We unwind position if there is a one
        vm.prank(address(vault));
        strategy.divest(type(uint256).max);

        assertTrue(strategy.canStartNewPos());
        assertEq(strategy.totalLockedValue(), 0);
        assertApproxEqRel(asset.balanceOf(address(vault)), 1000e6, 0.02e18);
    }
}
