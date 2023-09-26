// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {console2} from "forge-std/console2.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {SSVDeltaNeutralLp} from "src/strategies/SSVDeltaNeutralLp.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";

import {SSV} from "script/TestStrategyVault.s.sol";

contract SSVDeltaNeutralLpTest is TestPlus {
    SSVDeltaNeutralLp strategy;
    StrategyVault vault;
    WithdrawalEscrow escrow;

    ERC20 asset;
    ERC20 aToken;
    uint256 initialStrategyAssets;

    uint256 public constant IDEAL_SLIPPAGE_BPS = 200;
    uint256 public constant DEPOSIT_BPS = 5714;
    uint256 public constant BORROW_BPS = 7500;
    uint256 public constant MAX_BPS = 10_000;

    function setUp() public {
        forkEth();

        asset = ERC20(SSV._getEthMainNetUSDCAddr());
        vault = deployEthSSV(asset);
        strategy = SSV.deployEthSSVSushiUSDCStrategy(vault, DEPOSIT_BPS, BORROW_BPS);
        escrow = new WithdrawalEscrow(vault);
        // 1000 usdc
        initialStrategyAssets = 1000 * (10 ** asset.decimals());

        // add strategy, escrow to vault
        vm.startPrank(governance);
        vault.setStrategy(strategy);
        vault.setDebtEscrow(escrow);
        vm.stopPrank();

        aToken = strategy.aToken();
    }

    function testBeginPosition() public {
        // assign assets to the strategy
        deal(address(asset), address(strategy), initialStrategyAssets);

        // check for epoch ended
        assertEq(vault.epochEnded(), true);

        vm.prank(governance);
        strategy.startPosition(initialStrategyAssets, IDEAL_SLIPPAGE_BPS);

        // check the deposit assets
        assertEq(aToken.balanceOf(address(strategy)), (initialStrategyAssets * DEPOSIT_BPS) / MAX_BPS);

        // check for vault epoch
        assertEq(vault.epoch(), 1);

        // check for epoch ended
        assertEq(vault.epochEnded(), false);
    }

    function testClosePosition() public {
        // assign assets to the strategy
        deal(address(asset), address(this), initialStrategyAssets);

        asset.approve(address(vault), initialStrategyAssets);
        vault.deposit(initialStrategyAssets, address(this));

        vm.startPrank(governance);
        strategy.startPosition(initialStrategyAssets, IDEAL_SLIPPAGE_BPS);

        vault.redeem(vault.balanceOf(address(this)), address(this), address(this));

        strategy.endPosition(IDEAL_SLIPPAGE_BPS);

        console2.log("escrow shares at end: ", vault.balanceOf(address(escrow)));

        assertTrue(vault.epochEnded());
        // strategy shares should be zero
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(vault.balanceOf(address(escrow)), 0);

        assertApproxEqRel(asset.balanceOf(address(escrow)), initialStrategyAssets, 0.05e18);
    }
}
