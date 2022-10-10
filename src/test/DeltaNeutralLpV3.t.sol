// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

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

    function setUp() public {
        vm.createSelectFork("polygon", 31_824_532);
        vault = deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new DeltaNeutralLpV3(
        vault,
        0.05e18,
        0.001e18,
        ILendingPoolAddressesProviderRegistry(0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19),
        ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), // wrapped matic
        AggregatorV3Interface(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0), // matic/usd price feed
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapV3Pool(0xA374094527e1673A86dE625aa59517c5dE346d32) // WMATIC/USDC
        );

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        asset = usdc;
        borrowAsset = strategy.borrowAsset();
    }

    function testCreatePosition() public {
        uint256 startAssets = 1000e6;
        deal(address(usdc), address(strategy), startAssets);
        uint256 assetsToMatic = (startAssets) / 1000;

        strategy.startPosition();
        assertFalse(strategy.canStartNewPos());

        // I got the right amount of matic
        // assertApproxEqAbs(900e18, strategy.borrowAsset().balanceOf(address(strategy)), 0.05e18);

        // I have the right amount of aUSDC
        assertEq(strategy.aToken().balanceOf(address(strategy)), (startAssets - assetsToMatic) * 4 / 7);

        // I put the correct amount of money into uniswap pool
        uint256 assetsLP = strategy.valueOfLpPosition();
        uint256 assetsInAAve = strategy.aToken().balanceOf(address(strategy)) * 3 / 4;
        emit log_named_uint("assetsLP: ", assetsLP);
        emit log_named_uint("assetsInAAve: ", assetsInAAve);
        assertApproxEqRel(assetsLP, assetsInAAve * 2, 0.01e18);
    }

    function testEndPosition() public {
        deal(address(asset), address(strategy), 1000e6);
        strategy.startPosition();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        strategy.endPosition();

        strategy.endPosition();

        assertTrue(strategy.canStartNewPos());

        assertApproxEqRel(asset.balanceOf(address(strategy)), 1000e6, 0.02e18);
        assertEq(borrowAsset.balanceOf(address(strategy)), 0);
        assertEq(strategy.lpLiquidity(), 0);
    }

    function testTVL() public {
        assertEq(strategy.totalLockedValue(), 0);
        deal(address(asset), address(strategy), 1000e6);
        strategy.startPosition();

        assertApproxEqRel(strategy.totalLockedValue(), 1000e6, 0.02e18);
    }

    function testDivest() public {
        // If there's no position active, we just send our current balance
        deal(address(asset), address(strategy), 1);
        vm.prank(address(vault));
        strategy.divest(1);
        assertEq(asset.balanceOf(address(vault)), 1);

        deal(address(asset), address(strategy), 1000e6);
        strategy.startPosition();

        // We unwind position if there is a one
        vm.prank(address(vault));
        strategy.divest(type(uint256).max);

        assertTrue(strategy.canStartNewPos());
        assertEq(strategy.totalLockedValue(), 0);
        assertApproxEqRel(asset.balanceOf(address(vault)), 1000e6, 0.02e18);
    }
}
