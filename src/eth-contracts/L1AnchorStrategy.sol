// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { SafeERC20, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseStrategy } from "../BaseStrategy.sol";
import { IConversionPool } from "../interfaces/anchor/IConversionPool.sol";
import { IExchangeRateFeeder } from "../interfaces/anchor/IExchangeRateFeeder.sol";

contract L1AnchorStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    // aUSDC.
    IERC20 public immutable aToken;
    // EthAnchor USDC conversion pool.
    IConversionPool public immutable usdcConversionPool;
    // Exchange rate feeder.
    IExchangeRateFeeder public immutable exchangeRateFeeder;

    // The mininum amount of want token to trigger position adjustment
    uint256 public minWant = 100;

    constructor(
        address _vault,
        IERC20 _aToken,
        IConversionPool _usdcConversionPool,
        IExchangeRateFeeder _exchangeRateFeeder
    ) BaseStrategy(_vault) {
        aToken = _aToken;
        usdcConversionPool = _usdcConversionPool;
        exchangeRateFeeder = _exchangeRateFeeder;
    }

    function name() external pure override returns (string memory) {
        return "L1AnchorStrategy";
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // account for profit / losses
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssets = balanceOfWant() + balanceOfAToken();

        if (totalDebt > totalAssets) {
            _loss = totalDebt - totalAssets;
        } else {
            _profit = totalAssets - totalDebt;
        }

        // free funds to repay debt + profit to the strategy
        uint256 amountAvailable = balanceOfWant();
        uint256 amountRequired = _debtOutstanding + _profit;

        if (amountRequired > amountAvailable) {
            // we need to free funds
            // we dismiss losses here, they cannot be generated from withdrawal
            // but it is possible for the strategy to unwind full position
            (amountAvailable, ) = liquidatePosition(amountRequired);

            if (amountAvailable >= amountRequired) {
                _debtPayment = _debtOutstanding;
                // profit remains unchanged unless there is not enough to pay it
                if (amountRequired - _debtPayment < _profit) {
                    _profit = amountRequired - _debtPayment;
                }
            } else {
                // we were not able to free enough funds
                if (amountAvailable < _debtOutstanding) {
                    // available funds are lower than the repayment that we need to do
                    _profit = 0;
                    _debtPayment = amountAvailable;
                    // we dont report losses here as the strategy might not be able to return in this harvest
                    // but it will still be there for the next harvest
                } else {
                    // NOTE: amountRequired is always equal or greater than _debtOutstanding
                    // important to use amountRequired just in case amountAvailable is > amountAvailable
                    _debtPayment = _debtOutstanding;
                    _profit = amountAvailable - _debtPayment;
                }
            }
        } else {
            _debtPayment = _debtOutstanding;
            // profit remains unchanged unless there is not enough to pay it
            if (amountRequired - _debtPayment < _profit) {
                _profit = amountRequired - _debtPayment;
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = balanceOfWant();

        if (wantBalance > _debtOutstanding && wantBalance - _debtOutstanding > minWant) {
            _depositWant(wantBalance - _debtOutstanding);
            return;
        }

        if (_debtOutstanding > wantBalance) {
            // we should free funds
            uint256 amountRequired = _debtOutstanding - wantBalance;

            // NOTE: vault will take free funds during the next harvest
            _freeFunds(amountRequired);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _amountNeeded) {
            // if there is enough free want, let's use it
            return (_amountNeeded, 0);
        }

        // we need to free funds
        uint256 amountRequired = _amountNeeded - wantBalance;
        uint256 freeAssets = _freeFunds(amountRequired);

        if (_amountNeeded > freeAssets) {
            _liquidatedAmount = freeAssets;
            uint256 diff = _amountNeeded - _liquidatedAmount;
            if (diff <= minWant) {
                _loss = diff;
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256 _amountFreed) {
        (_amountFreed, ) = liquidatePosition(type(uint256).max);
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant() + balanceOfAToken();
    }

    function protectedTokens() internal view override returns (address[] memory) {}

    // Internal views
    function balanceOfWant() internal view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfAToken() internal view returns (uint256) {
        return aToken.balanceOf(address(this)) * exchangeRateFeeder.exchangeRateOf(address(aToken), true);
    }

    function _depositWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        usdcConversionPool.deposit(amount);
        return amount;
    }

    function _withdrawWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        uint256 aTokenAmount = amount / exchangeRateFeeder.exchangeRateOf(address(aToken), true);
        usdcConversionPool.redeem(aTokenAmount);
        return amount;
    }

    function _freeFunds(uint256 amountToFree) internal returns (uint256) {
        if (amountToFree == 0) return 0;

        uint256 aTokenAmount = balanceOfAToken();
        uint256 withdrawAmount = Math.min(amountToFree, aTokenAmount);

        _withdrawWant(withdrawAmount);
        return balanceOfWant();
    }

    function nativeToWant(uint256 _amtInWei) public pure override returns (uint256) {
        _amtInWei;
        revert("Not Implemented");
    }
}
