// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {DeltaNeutralLp, ILendingPoolAddressesProviderRegistry} from "../polygon/DeltaNeutralLp.sol";

contract DeltaNeutralTest is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
    DeltaNeutralLp strategy;
    ERC20 usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    ERC20 abPair;
    ERC20 asset;
    ERC20 borrowAsset;

    function setUp() public {
        vm.createSelectFork("polygon", 31_824_532);
        vault = deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new DeltaNeutralLp(
        vault,
        0.05e18,
        0.001e18,
        ILendingPoolAddressesProviderRegistry(0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19),
        ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270),
        AggregatorV3Interface(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0),
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap
        IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4) // sushiswap
        );

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        abPair = strategy.abPair();
        asset = usdc;
        borrowAsset = strategy.borrowAsset();
    }

    function testCreatePosition() public {
        uint256 startAssets = 1000e6;
        deal(address(usdc), address(strategy), startAssets);

        uint256 assetsToMatic = (startAssets) / 1000;
        address[] memory path = new address[](2);
        path[0] = address(strategy.asset());
        path[1] = address(strategy.borrowAsset());

        // I should get this much matic
        uint256[] memory amounts = strategy.router().getAmountsOut(assetsToMatic, path);
        uint256 amountMatic = amounts[1];

        strategy.startPosition();
        assertFalse(strategy.canStartNewPos());

        // I got the right amount of matic
        assertApproxEqAbs(amountMatic, strategy.borrowAsset().balanceOf(address(strategy)), 1e18);

        // I have the right amount of aUSDC
        assertEq(strategy.aToken().balanceOf(address(strategy)), (startAssets - assetsToMatic) * 4 / 7);

        // I have the right amount of uniswap lp tokens
        uint256 assetsLP =
            abPair.balanceOf(address(strategy)) * (asset.balanceOf(address(abPair)) * 2) / abPair.totalSupply();
        uint256 assetsInAAve = strategy.aToken().balanceOf(address(strategy)) * 3 / 4;
        emit log_named_uint("assetsLP: ", assetsLP);
        emit log_named_uint("assetsInAAve: ", assetsInAAve * 2);
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
        assertEq(abPair.balanceOf(address(strategy)), 0);
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
