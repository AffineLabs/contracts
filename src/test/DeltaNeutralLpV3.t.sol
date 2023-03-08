// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "forge-std/Components.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {EthVaults} from "script/EthVaults.s.sol";
import {Vault} from "src/vaults/Vault.sol";
import {DeltaNeutralLpV3} from "src/strategies/DeltaNeutralLpV3.sol";
import {SslpV3} from "script/DeltaNeutralLpV3.s.sol";

/// @notice Test SSLP Strategy with Uniswap V3 in polygon.
contract DeltaNeutralV3Test is TestPlus {
    using stdStorage for StdStorage;

    Vault vault;
    DeltaNeutralLpV3 strategy;
    ERC20 asset;
    ERC20 borrow;
    int24 tickLow;
    int24 tickHigh;
    uint256 slippageBps = 1000;
    uint256 initStrategyBalance;

    function _selectFork() internal virtual {
        forkPolygon();
    }

    function _asset() internal virtual returns (address) {
        return 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    }

    function _setAsset() internal virtual {
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(_asset())))
        );
    }

    function _deployVault() internal virtual {
        vault = Vault(address(deployL2Vault()));
    }

    function _deployStrategy() internal virtual {
        strategy = SslpV3.deployPoly(vault);
    }

    function setUp() public {
        _selectFork();
        _deployVault();
        _setAsset();
        _deployStrategy();

        // Get ticks where liquidity will be added
        IUniswapV3Pool pool = strategy.pool();
        (, int24 tick,,,,,) = pool.slot0();
        int24 tSpace = pool.tickSpacing();
        int24 usableTick = (tick / tSpace) * tSpace;
        tickLow = usableTick - 20 * tSpace;
        tickHigh = usableTick + 20 * tSpace;

        vm.startPrank(vault.governance());
        vault.addStrategy(strategy, 5000);
        strategy.grantRole(strategy.STRATEGIST_ROLE(), address(this));
        vm.stopPrank();

        asset = strategy.asset();
        borrow = strategy.borrow();
        initStrategyBalance = 1000 * (10 ** asset.decimals());
    }

    /// @notice Test that a position can be opened.
    function testCreatePosition() public {
        uint256 startAssets = initStrategyBalance;
        deal(address(asset), address(strategy), startAssets);

        strategy.startPosition(startAssets, tickLow, tickHigh, slippageBps);
        // Can't start a new position
        assertFalse(strategy.canStartNewPos());
        // Ntft exists and we own it
        uint256 lpId = strategy.lpId();
        assertGt(lpId, 0);
        assertEq(strategy.lpManager().ownerOf(lpId), address(strategy));

        // I have the right amount of aUSDC
        assertEq(
            strategy.aToken().balanceOf(address(strategy)), startAssets * strategy.assetToDepositRatioBps() / 10_000
        );

        // I put the correct amount of money into uniswap pool
        uint256 assetsLP = strategy.valueOfLpPosition();
        uint256 assetsInAAve =
            strategy.aToken().balanceOf(address(strategy)) * strategy.collateralToBorrowRatioBps() / 10_000;
        emit log_named_uint("assetsLP: ", assetsLP);
        emit log_named_uint("assetsInAAve: ", assetsInAAve);
        // Not all of the ether gets added as liquidity, and not all of the usdc gets added either
        // See https://uniswapv3book.com/docs/milestone_1/calculating-liquidity/
        // We do use 5% slippage though
        assertApproxEqRel(assetsLP, assetsInAAve * 2, 0.05e18);
    }

    /**
     * @notice test start position with more assets than balance
     */
    function testStartInvalidPosition() public {
        uint256 startAssets = initStrategyBalance;
        deal(address(asset), address(strategy), startAssets);

        // call should revert
        vm.expectRevert("DNLP: insufficient assets");
        strategy.startPosition(startAssets + 1, tickLow, tickHigh, slippageBps);
    }

    /// @notice Test that a position can be ended.
    function testEndPosition() public {
        deal(address(asset), address(strategy), initStrategyBalance);
        strategy.startPosition(initStrategyBalance, tickLow, tickHigh, slippageBps);
        uint256 origLpId = strategy.lpId();

        vm.expectRevert();
        vm.prank(alice);
        strategy.endPosition(slippageBps);

        strategy.endPosition(slippageBps);
        assertTrue(strategy.canStartNewPos());
        assertEq(strategy.lpId(), 0);

        INonfungiblePositionManager manager = strategy.lpManager();
        // the solidity 0.7 version of the manager reverts with this error
        vm.expectRevert("ERC721: owner query for nonexistent token");
        manager.ownerOf(origLpId);

        assertApproxEqRel(asset.balanceOf(address(strategy)), initStrategyBalance, 0.02e18);
        assertEq(borrow.balanceOf(address(strategy)), 0);
        assertEq(strategy.lpLiquidity(), 0);
    }

    /// @notice Test TVL calculation.
    function testTVL() public {
        assertEq(strategy.totalLockedValue(), 0);
        deal(address(asset), address(strategy), initStrategyBalance);
        strategy.startPosition(initStrategyBalance, tickLow, tickHigh, slippageBps);

        assertApproxEqRel(strategy.totalLockedValue(), initStrategyBalance, 0.02e18);
    }

    /// @notice Test that value can divest from this strategy.
    function testDivest() public {
        // If there's no position active, we just send our current balance
        deal(address(asset), address(strategy), 1);
        vm.prank(address(vault));
        strategy.divest(1);
        assertEq(asset.balanceOf(address(vault)), 1);

        deal(address(asset), address(strategy), initStrategyBalance);
        strategy.startPosition(initStrategyBalance, tickLow, tickHigh, slippageBps);

        // We unwind position if there is a one
        vm.prank(address(vault));
        strategy.divest(type(uint256).max);

        assertTrue(strategy.canStartNewPos());
        assertEq(strategy.totalLockedValue(), 0);
        assertApproxEqRel(asset.balanceOf(address(vault)), initStrategyBalance, 0.02e18);
    }

    function testFeeView() public {
        deal(address(asset), address(strategy), initStrategyBalance);
        strategy.startPosition(initStrategyBalance, tickLow, tickHigh, slippageBps);

        (uint256 assetsFee, uint256 borrowsFee) = strategy.positionFees();
        console.log("assetsFee: %s, borrowsFee: %s", assetsFee, borrowsFee);
        assertTrue(assetsFee == 0 && borrowsFee == 0);

        deal(address(asset), address(this), initStrategyBalance);
        asset.approve(address(strategy.router()), type(uint256).max);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(asset),
            tokenOut: address(borrow),
            fee: strategy.poolFee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: initStrategyBalance,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        strategy.router().exactInputSingle(params);

        (assetsFee, borrowsFee) = strategy.positionFees();
        console.log("assetsFee: %s, borrowsFee: %s", assetsFee, borrowsFee);
        assertTrue(assetsFee > 0);
        assertTrue(borrowsFee == 0);
    }
}

contract DeltaNeutralV3EthTest is DeltaNeutralV3Test {
    function _selectFork() internal override {
        forkEth();
    }

    function _asset() internal pure override returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _deployStrategy() internal override {
        strategy = SslpV3.deployEth(vault);
    }
}

contract DeltaNeutralV3EthWethTest is DeltaNeutralV3Test {
    function _selectFork() internal override {
        vm.createSelectFork("ethereum", 16_394_906);
    }

    function _setAsset() internal virtual override {}

    function _deployVault() internal override {
        vault = EthVaults.deployEthWeth();
    }

    function _deployStrategy() internal override {
        strategy = SslpV3.deployEthWeth(vault);
    }
}
