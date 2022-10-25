// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {DeltaNeutralLp, ILendingPoolAddressesProviderRegistry} from "../ethereum/DeltaNeutralLp.sol";
import {IMasterChef} from "../interfaces/sushiswap/IMasterChef.sol";

contract DeltaNeutralTest is TestPlus {
    using stdStorage for StdStorage;

    L1Vault vault;
    DeltaNeutralLp strategy;
    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 abPair;
    ERC20 asset;
    ERC20 borrowAsset;

    function setUp() public {
        vm.createSelectFork("ethereum", 15_821_794);
        vault = deployL1Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new DeltaNeutralLp(
        vault,
        0.001e18,
        ILendingPoolAddressesProviderRegistry(0x52D306e36E3B6B02c153d0266ff0f85d18BCD413),
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
        IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F), // sushiswap
        IUniswapV2Factory(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac), // sushiswap
        IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd), // MasterChef
        1 // Masterchef PID
        );

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        abPair = strategy.abPair();
        asset = usdc;
        borrowAsset = strategy.borrowAsset();
    }

    function testOnlyAddressWithStrategistRoleCanStartPosition() public {
        uint256 startAssets = 1000e6;
        deal(address(usdc), address(strategy), startAssets);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role ",
                Strings.toHexString(uint256(strategy.STRATEGIST_ROLE()), 32)
            )
        );
        strategy.startPosition();
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

        vm.startPrank(vault.governance());

        strategy.startPosition();
        assertFalse(strategy.canStartNewPos());

        // I got the right amount of matic
        assertApproxEqAbs(amountMatic, strategy.borrowAsset().balanceOf(address(strategy)), 1e18);

        // I have the right amount of aUSDC
        assertEq(strategy.aToken().balanceOf(address(strategy)), (startAssets - assetsToMatic) * 4 / 7);

        // I have the right amount of uniswap lp tokens
        uint256 masterChefStakedAmount =
            strategy.masterChef().userInfo(strategy.masterChefPid(), address(strategy)).amount;
        uint256 assetsLP = masterChefStakedAmount * (asset.balanceOf(address(abPair)) * 2) / abPair.totalSupply();
        uint256 assetsInAAve = strategy.aToken().balanceOf(address(strategy)) * 3 / 4;
        emit log_named_uint("masterChefStakedAmount", masterChefStakedAmount);
        emit log_named_uint("assetsLP: ", assetsLP);
        emit log_named_uint("assetsInAAve: ", assetsInAAve * 2);
        assertApproxEqRel(assetsLP, assetsInAAve * 2, 0.01e18);
    }

    function testOnlyAddressWithStrategistRoleCanEndPosition() public {
        deal(address(asset), address(strategy), 1000e6);

        vm.startPrank(vault.governance());
        strategy.startPosition();

        changePrank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role ",
                Strings.toHexString(uint256(strategy.STRATEGIST_ROLE()), 32)
            )
        );
        strategy.endPosition();
    }

    function testEndPosition() public {
        deal(address(asset), address(strategy), 1000e6);

        vm.startPrank(vault.governance());
        strategy.startPosition();

        changePrank(vault.governance());
        strategy.endPosition();

        assertTrue(strategy.canStartNewPos());
        assertApproxEqRel(asset.balanceOf(address(strategy)), 1000e6, 0.02e18);
        assertEq(borrowAsset.balanceOf(address(strategy)), 0);
        assertEq(abPair.balanceOf(address(strategy)), 0);
    }

    function testTVL() public {
        assertEq(strategy.totalLockedValue(), 0);
        deal(address(asset), address(strategy), 1000e6);

        vm.prank(vault.governance());
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

        vm.prank(vault.governance());
        strategy.startPosition();

        // We unwind position if there is a one
        vm.prank(address(vault));
        strategy.divest(type(uint256).max);

        assertTrue(strategy.canStartNewPos());
        assertEq(strategy.totalLockedValue(), 0);
        assertApproxEqRel(asset.balanceOf(address(vault)), 1000e6, 0.02e18);
    }
}
