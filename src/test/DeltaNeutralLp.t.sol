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

    function _fork() internal virtual {
        forkEth();
    }

    function _deployVault() internal virtual {
        vault = deployL1Vault();
    }

    function _usdc() internal virtual returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _deployStrategy() internal virtual {
        strategy = Sslp.deployEth(vault);
    }

    function setUp() public {
        _fork();
        _deployVault();

        usdc = ERC20(_usdc());
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        _deployStrategy();

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
        assertApproxEqRel(strategy.aToken().balanceOf(address(strategy)), startAssets * 4 / 7, 0.01e18);

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

    /// @notice Fuzz test TVL function.
    function testTVLFuzz(uint256 assets) public {
        // Reserve size for weth can be estimated from aWETH token
        // See aAMMWETH token: https://etherscan.io/address/0xf9Fb4AD91812b704Ba883B11d2B576E890a6730A
        // Max borrowable WETH available in AAVE in this block is around 819WETH or 1.3e6 USDC.
        // Size of biggest position is debt * 4/3 * 7/4 = debt * 7/3
        assets = bound(assets, 0, 2.6e6 * 1e6);

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
contract L2DeltaNeutralTest is L1DeltaNeutralTest {
    using stdStorage for StdStorage;

    function _fork() internal override {
        forkPolygon();
    }

    function _deployVault() internal override {
        vault = deployL2Vault();
    }

    function _usdc() internal override returns (address) {
        return 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    }

    function _deployStrategy() internal override {
        strategy = Sslp.deployPoly(vault);
    }
}
