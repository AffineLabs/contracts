// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {BaseVault} from "../BaseVault.sol";
import {DeltaNeutralLp, ILendingPoolAddressesProviderRegistry} from "../both/DeltaNeutralLp.sol";
import {IMasterChef} from "../interfaces/sushiswap/IMasterChef.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {Sslp} from "../../script/DeltaNeutralLp.s.sol";

/// @notice Test SSLP Strategy with Sushiswap in L1.
contract L1DeltaNeutralTest is TestPlus {
    using stdStorage for StdStorage;

    BaseVault vault;
    DeltaNeutralLp strategy;
    ERC20 usdc;
    ERC20 abPair;
    ERC20 asset;
    ERC20 borrow;
    uint256 masterChefPid;

    uint256 public constant IDEAL_SLIPPAGE_BPS = 200;

    function setUp() public {
        forkEth();
        vault = deployL1Vault();
        usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = Sslp.deployEth(vault);

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        abPair = strategy.abPair();
        asset = usdc;
        borrow = strategy.borrow();
    }

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

        vm.startPrank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);
        assertFalse(strategy.canStartNewPos());

        // I have the right amount of aUSDC
        assertEq(strategy.aToken().balanceOf(address(strategy)), startAssets * 4 / 7);

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
        assertEq(borrow.balanceOf(address(strategy)), 0);
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
        // If there's no position active, we fjust send our current balance
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

    /// @notice Strategist can claim rewards.
    function testClaimAndSellSushi() public {
        deal(address(asset), address(strategy), 1000e6);

        vm.prank(vault.governance());
        strategy.startPosition(IDEAL_SLIPPAGE_BPS);

        // The staked lp tokens gain will accumulate some sushi
        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1 days);
        if (strategy.useMasterChefV2()) {
            // Update pool to be able to harvest sushi rewards.
            strategy.masterChef().updatePool(strategy.masterChefPid());
        }

        assertGt(strategy.masterChef().pendingSushi(1, address(strategy)), 0);

        uint256 oldAssetBal = strategy.balanceOfAsset();
        vm.prank(vault.governance());
        strategy.claimAndSellSushi(IDEAL_SLIPPAGE_BPS);

        assertGt(strategy.balanceOfAsset(), oldAssetBal);
        assertEq(strategy.sushiToken().balanceOf(address(strategy)), 0);
    }

    /// @notice Fuzz test to calculate TVL in random scenarios.
    function testTVLFuzz(uint256 assets) public {
        // Max borrowable WETH available in AAVE in this block is around 1334.66 WETH or 2178919.22 USDC.
        // So technically we should be able to take position with around 2178919.22 / ((4 / 7) * (3 / 4)) = 5084144.84 USDC
        assets = bound(assets, 0, 4e12);

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

/// @notice Test SSLP Strategy with Sushiswap in L2.
contract L2DeltaNeutralTest is TestPlus {
    using stdStorage for StdStorage;

    BaseVault vault;
    DeltaNeutralLp strategy;
    ERC20 usdc;
    ERC20 abPair;
    ERC20 asset;
    ERC20 borrow;
    uint256 masterChefPid;

    uint256 public constant IDEAL_SLIPPAGE_BPS = 200;

    function setUp() public {
        forkPolygon();
        vault = deployL2Vault();
        usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = Sslp.deployPoly(vault);

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);

        abPair = strategy.abPair();
        asset = usdc;
        borrow = strategy.borrow();
    }

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

        vm.startPrank(vault.governance());

        strategy.startPosition(IDEAL_SLIPPAGE_BPS);
        assertFalse(strategy.canStartNewPos());

        // I have the right amount of aUSDC
        assertEq(strategy.aToken().balanceOf(address(strategy)), startAssets * 4 / 7);

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
        assertEq(borrow.balanceOf(address(strategy)), 0);
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

    /// @notice Fuzz test to calculate TVL in random scenarios.
    function testTVLFuzz(uint256 assets) public {
        // Max borrowable WETH available in AAVE in this block is around 1334.66 WETH or 2178919.22 USDC.
        // So technically we should be able to take position with around 2178919.22 / ((4 / 7) * (3 / 4)) = 5084144.84 USDC
        assets = bound(assets, 0, 4e12);

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
