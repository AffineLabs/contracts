// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {BaseVault} from "../BaseVault.sol";
import {DeltaNeutralLp, ILendingPoolAddressesProviderRegistry} from "../DeltaNeutralLp.sol";
import {IMasterChef} from "../interfaces/sushiswap/IMasterChef.sol";

abstract contract DeltaNeutralTestBase is TestPlus {
    BaseVault vault;
    DeltaNeutralLp strategy;
    ERC20 usdc;
    ERC20 abPair;
    ERC20 asset;
    ERC20 borrowAsset;
    uint256 masterChefPid;

    uint256 public constant IDEAL_SLIPPAGE_BPS = 200;

    /// @notice Test only address with strategist role can open a position.
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
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);
    }

    /// @notice Test creation of position.
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

        strategy.startPosition(IDEAL_SLIPPAGE_BPS);
        assertFalse(strategy.canStartNewPos());

        // I got the right amount of matic
        assertApproxEqAbs(amountMatic, strategy.borrowAsset().balanceOf(address(strategy)), 0.01e18);

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

    /// @notice Test only address with strategist role can end a position.
    function testOnlyAddressWithStrategistRoleCanEndPosition() public {
        deal(address(asset), address(strategy), 1000e6);

        vm.startPrank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);

        changePrank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role ",
                Strings.toHexString(uint256(strategy.STRATEGIST_ROLE()), 32)
            )
        );
        strategy.endPosition(IDEAL_SLIPPAGE_BPS);
    }

    /// @notice Test ending a position.
    function testEndPosition() public {
        deal(address(asset), address(strategy), 1000e6);

        vm.startPrank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);
        strategy.endPosition(IDEAL_SLIPPAGE_BPS);

        assertTrue(strategy.canStartNewPos());
        assertApproxEqRel(asset.balanceOf(address(strategy)), 1000e6, 0.01e18);
        assertEq(borrowAsset.balanceOf(address(strategy)), 0);
        assertEq(abPair.balanceOf(address(strategy)), 0);
        assertEq(strategy.debtToken().balanceOf(address(strategy)), 0);
    }

    /// @notice Test TVL calculation.
    function testTVL() public {
        assertEq(strategy.totalLockedValue(), 0);
        deal(address(asset), address(strategy), 1000e6);

        assertApproxEqRel(strategy.totalLockedValue(), 1000e6, 0.01e18);

        vm.prank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);

        assertApproxEqRel(strategy.totalLockedValue(), 1000e6, 0.01e18);
    }

    /// @notice Test vault can divest from this strategy.
    function testDivest() public {
        // If there's no position active, we just send our current balance
        deal(address(asset), address(strategy), 1);
        vm.prank(address(vault));
        strategy.divest(1);
        assertEq(asset.balanceOf(address(vault)), 1);

        deal(address(asset), address(strategy), 1000e6);

        vm.prank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);

        // We unwind position if there is a one
        vm.prank(address(vault));
        strategy.divest(type(uint256).max);

        assertTrue(strategy.canStartNewPos());
        assertEq(strategy.totalLockedValue(), 0);
        assertApproxEqRel(asset.balanceOf(address(vault)), 1000e6, 0.01e18);
    }

    /// @notice Test strategist can calim rewards.
    function testClaimRewards() public {
        // If there's no position active, we just send our current balance
        deal(address(asset), address(strategy), 1);
        vm.prank(address(vault));
        strategy.divest(1);
        assertEq(asset.balanceOf(address(vault)), 1);

        deal(address(asset), address(strategy), 1000e6);

        vm.prank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);

        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1 days);
        if (strategy.useMasterChefV2()) {
            // Update pool to be able to harvest sushi rewards.
            strategy.masterChef().updatePool(strategy.masterChefPid());
        }

        // We unwind position if there is a one
        changePrank(address(vault));
        strategy.divest(type(uint256).max);

        uint256 sushiBalance = strategy.sushiToken().balanceOf(address(strategy));
        emit log_named_uint("[Pre] Suhsi balance", sushiBalance);
        assertGt(sushiBalance, 0);

        changePrank(vault.governance());
        strategy.claimRewards(IDEAL_SLIPPAGE_BPS);

        sushiBalance = strategy.sushiToken().balanceOf(address(strategy));
        emit log_named_uint("[Post] Suhsi balance", sushiBalance);
        assertEq(sushiBalance, 0);
    }

    /// @notice Fuzz test to calculate TVL in random scenarios.
    function testTVLFuzz(uint64 assets) public {
        // Max borrowable WETH available in AAVE in this block is around 1334.66 WETH or 2178919.22 USDC.
        // So technically we should be able to take position with around 2178919.22 / ((4 / 7) * (3 / 4)) = 5084144.84 USDC
        vm.assume(assets < 4e12);

        if (assets > 1e5) {
            assertEq(strategy.totalLockedValue(), 0);

            deal(address(asset), address(strategy), assets);
            assertApproxEqRel(strategy.totalLockedValue(), assets, 0.01e18);

            vm.startPrank(vault.governance());
            strategy.startPosition(IDEAL_SLIPPAGE_BPS);
            assertApproxEqRel(strategy.totalLockedValue(), assets, 0.01e18);

            strategy.endPosition(IDEAL_SLIPPAGE_BPS);
            assertApproxEqRel(strategy.totalLockedValue(), assets, 0.01e18);
        }
    }
}

/// @notice Test SSLP Strategy with Sushiswap in L1.
contract L1DeltaNeutralTest is DeltaNeutralTestBase {
    using stdStorage for StdStorage;

    function setUp() public {
        vm.createSelectFork("ethereum", 15_624_364);
        vault = deployL1Vault();
        usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new DeltaNeutralLp(
        vault,
        0.001e18,
        ILendingPoolAddressesProviderRegistry(0x52D306e36E3B6B02c153d0266ff0f85d18BCD413),
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
        IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F), // sushiswap router
        IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd), // MasterChef
        1, // Masterchef PID
        false, // use MasterChefV1 interface
        ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2)
        );

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        abPair = strategy.abPair();
        asset = usdc;
        borrowAsset = strategy.borrowAsset();
    }
}

/// @notice Test SSLP Strategy with Sushiswap in L2.
contract L2DeltaNeutralTest is DeltaNeutralTestBase {
    using stdStorage for StdStorage;

    function setUp() public {
        vm.createSelectFork("polygon", 31_824_532);
        vault = deployL2Vault();
        usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new DeltaNeutralLp(
        vault,
        0.001e18,
        ILendingPoolAddressesProviderRegistry(0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19),
        ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
        AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945),
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
        IMasterChef(0x0769fd68dFb93167989C6f7254cd0D766Fb2841F), // MasterChef
        1, // Masterchef PID
        true, // use MasterChefV2 interface
        ERC20(0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a)
        );

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        abPair = strategy.abPair();
        asset = usdc;
        borrowAsset = strategy.borrowAsset();
    }
}
