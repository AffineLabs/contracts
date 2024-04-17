// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {WETH as IWMATIC} from "solmate/src/tokens/WETH.sol";

import {AffineVault, Strategy} from "src/vaults/AffineVault.sol";
import {SlippageUtils} from "src/libs/audited/SlippageUtils.sol";

import {StaderLevMaticStrategy} from "src/strategies/StaderLevMaticStrategy.sol";

contract LevMaticXLoopStrategy is StaderLevMaticStrategy {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWMATIC;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    uint256 public iCycle = 10;
    uint256 public levBps = 65_132; // for 10 loops 6.5x

    constructor(AffineVault _vault, address[] memory strategists) StaderLevMaticStrategy(_vault, strategists) {}

    function _afterInvest(uint256 amount) internal override {
        _flashLoan(amount.mulDivDown(levBps, MAX_BPS), LoanType.invest, address(0), FLOrigin.balancer);
    }

    /// @dev Unlock wstETH collateral via flashloan, then repay balancer loan with unlocked collateral.
    function _divestWithFL(uint256 amount) internal returns (uint256) {
        uint256 flashLoanAmount = _getDivestFlashLoanAmounts(amount);

        uint256 origAssets = WMATIC.balanceOf(address(this));
        _flashLoan(flashLoanAmount, LoanType.divest, address(0), FLOrigin.aave);
        // The loan has been paid, any other unlocked collateral belongs to user
        uint256 unlockedAssets = WMATIC.balanceOf(address(this)) - origAssets;
        return unlockedAssets;
    }
    /// @dev Unlock wstETH collateral via flashloan, then repay balancer loan with unlocked collateral.

    function _divest(uint256 amount) internal override returns (uint256) {
        uint256 tvl = totalLockedValue();
        uint256 postTVL = amount < tvl ? tvl - amount : 0;

        uint256 preAssets = WMATIC.balanceOf(address(this));

        uint256 stMaticToRedeem;
        uint256 amountReceived;

        uint256 exCollateral = _collateral() - _debt().mulDivUp(MAX_BPS, borrowBps);
        uint256 toWithdraw = amount < tvl ? exCollateral.mulDivDown(amount, tvl) : exCollateral;

        for (uint256 i = 1; i <= iCycle; i++) {
            (stMaticToRedeem,,) = STADER.convertMaticToMaticX(toWithdraw);
            if (stMaticToRedeem > aToken.balanceOf(address(this)) || _debt() == 0) {
                stMaticToRedeem = aToken.balanceOf(address(this));
            }
            AAVE.withdraw(address(MATICX), stMaticToRedeem, address(this));
            amountReceived = _swapMaticXToMatic(MATICX.balanceOf(address(this)));

            if (i < iCycle && _debt() > 0) {
                AAVE.repay(address(WMATIC), amountReceived, 2, address(this));
            }

            toWithdraw = amountReceived.mulDivDown(MAX_BPS, borrowBps);
        }

        if (postTVL < totalLockedValue()) {
            _divestWithFL(totalLockedValue() - postTVL);
        }

        uint256 unlockedAssets = WMATIC.balanceOf(address(this)) - preAssets;

        WMATIC.safeTransfer(address(vault), Math.min(unlockedAssets, amount));

        return unlockedAssets;
    }

    function rebalance() external override onlyRole(STRATEGIST_ROLE) {}
}
