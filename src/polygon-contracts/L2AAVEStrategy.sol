// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { BaseStrategy } from "../BaseStrategy.sol";

import { SafeERC20, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ILendingPoolAddressesProvider } from "../interfaces/aave/ILendingPoolAddressesProvider.sol";
import { IAaveIncentivesController } from "../interfaces/aave/IAaveIncentivesController.sol";
import { ILendingPool } from "../interfaces/aave/ILendingPool.sol";
import { IAToken } from "../interfaces/aave/IAToken.sol";

interface ILendingPoolAddressesProviderRegistry {
    function getAddressesProvidersList() external view returns (address[] memory);
}

contract L2AAVEStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // AAVE protocol contracts
    IAaveIncentivesController public immutable incentivesController;
    ILendingPool public immutable lendingPool;

    // USDC pool reward token is WMATIC
    address public immutable rewardToken;
    address public immutable wrappedNative;

    // Corresponding AAVE token (USDC -> aUSDC)
    IAToken public immutable aToken;

    // Router for swapping reward tokens to `want`
    IUniLikeSwapRouter public immutable router;

    // The mininum amount of want token to trigger position adjustment
    uint256 public minWant = 100;
    uint256 public minRewardToSell = 1e15;

    uint256 public constant MAX_BPS = 1e4;
    uint256 public constant PESSIMISM_FACTOR = 1000;

    constructor(
        address _vault,
        address _registry,
        address _incentives,
        address _router,
        address _rewardToken,
        address _wrappedNative
    ) BaseStrategy(_vault) {
        address[] memory providers = ILendingPoolAddressesProviderRegistry(_registry).getAddressesProvidersList();
        address pool = ILendingPoolAddressesProvider(providers[providers.length - 1]).getLendingPool();
        lendingPool = ILendingPool(pool);

        address _aToken = lendingPool.getReserveData(address(want)).aTokenAddress;
        aToken = IAToken(_aToken);

        incentivesController = IAaveIncentivesController(_incentives);

        router = IUniLikeSwapRouter(_router);
        rewardToken = _rewardToken;
        wrappedNative = _wrappedNative;
    }

    function name() external pure override returns (string memory) {
        return "L2AAVEStrategy";
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
        _claimAndSellRewards();

        // account for profit / losses
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssets = balanceOfWant().add(balanceOfAToken());

        if (totalDebt > totalAssets) {
            _loss = totalDebt.sub(totalAssets);
        } else {
            _profit = totalAssets.sub(totalDebt);
        }

        // free funds to repay debt + profit to the strategy
        uint256 amountAvailable = balanceOfWant();
        uint256 amountRequired = _debtOutstanding.add(_profit);

        if (amountRequired > amountAvailable) {
            // we need to free funds
            // we dismiss losses here, they cannot be generated from withdrawal
            // but it is possible for the strategy to unwind full position
            (amountAvailable, ) = liquidatePosition(amountRequired);

            if (amountAvailable >= amountRequired) {
                _debtPayment = _debtOutstanding;
                // profit remains unchanged unless there is not enough to pay it
                if (amountRequired.sub(_debtPayment) < _profit) {
                    _profit = amountRequired.sub(_debtPayment);
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
                    _profit = amountAvailable.sub(_debtPayment);
                }
            }
        } else {
            _debtPayment = _debtOutstanding;
            // profit remains unchanged unless there is not enough to pay it
            if (amountRequired.sub(_debtPayment) < _profit) {
                _profit = amountRequired.sub(_debtPayment);
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = balanceOfWant();

        if (wantBalance > _debtOutstanding && wantBalance.sub(_debtOutstanding) > minWant) {
            _depositWant(wantBalance.sub(_debtOutstanding));
            return;
        }

        if (_debtOutstanding > wantBalance) {
            // we should free funds
            uint256 amountRequired = _debtOutstanding.sub(wantBalance);

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
        uint256 amountRequired = _amountNeeded.sub(wantBalance);
        uint256 freeAssets = _freeFunds(amountRequired);

        if (_amountNeeded > freeAssets) {
            _liquidatedAmount = freeAssets;
            uint256 diff = _amountNeeded.sub(_liquidatedAmount);
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

    function nativeToWant(uint256 _amtInWei) public view override returns (uint256) {
        return tokenToWant(wrappedNative, _amtInWei);
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 balanceExcludingRewards = balanceOfWant().add(balanceOfAToken());

        // if we don't have a position, don't worry about rewards
        if (balanceExcludingRewards < minWant) {
            return balanceExcludingRewards;
        }

        uint256 rewards = estimatedRewardsInWant().mul(MAX_BPS.sub(PESSIMISM_FACTOR)).div(MAX_BPS);

        return balanceExcludingRewards.add(rewards);
    }

    function estimatedRewardsInWant() public view returns (uint256) {
        uint256 rewardTokenBalance = balanceOfRewardToken();

        uint256 pendingRewards = incentivesController.getRewardsBalance(getAaveAssets(), address(this));

        if (rewardToken == address(want)) {
            return pendingRewards;
        } else {
            return tokenToWant(rewardToken, rewardTokenBalance.add(pendingRewards));
        }
    }

    function protectedTokens() internal view override returns (address[] memory) {}

    // Internal views
    function balanceOfWant() internal view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfRewardToken() internal view returns (uint256) {
        return IERC20(rewardToken).balanceOf(address(this));
    }

    function balanceOfAToken() internal view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function tokenToWant(address token, uint256 amount) internal view returns (uint256) {
        if (amount == 0 || address(want) == token) {
            return amount;
        }

        uint256[] memory amounts = router.getAmountsOut(amount, getTokenOutPathV2(token, address(want)));

        return amounts[amounts.length - 1];
    }

    function _depositWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.deposit(address(want), amount, address(this), 0);
        return amount;
    }

    function _withdrawWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.withdraw(address(want), amount, address(this));
        return amount;
    }

    function _freeFunds(uint256 amountToFree) internal returns (uint256) {
        if (amountToFree == 0) return 0;

        uint256 aTokenAmount = balanceOfAToken();
        uint256 withdrawAmount = Math.min(amountToFree, aTokenAmount);

        _withdrawWant(withdrawAmount);
        return balanceOfWant();
    }

    function _sellRewardTokenForWant(uint256 amountIn, uint256 minOut) internal {
        if (amountIn == 0) {
            return;
        }

        router.swapExactTokensForTokens(
            amountIn,
            minOut,
            getTokenOutPathV2(address(rewardToken), address(want)),
            address(this),
            block.timestamp
        );
    }

    function _claimAndSellRewards() internal {
        incentivesController.claimRewards(getAaveAssets(), type(uint256).max, address(this));

        if (rewardToken != address(want)) {
            uint256 rewardTokenBalance = balanceOfRewardToken();
            if (rewardTokenBalance >= minRewardToSell) {
                _sellRewardTokenForWant(rewardTokenBalance, 0);
            }
        }

        return;
    }

    function getAaveAssets() internal view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = address(aToken);
    }

    // This function will choose  a path of [A, B] if either A or B is WETH (or equivalent on other EVM chains)
    // If neither is WETH, then it gives a path of [A, WETH, B]
    function getTokenOutPathV2(address _token_in, address _token_out) internal view returns (address[] memory _path) {
        bool is_wrapped_native = _token_in == address(wrappedNative) || _token_out == address(wrappedNative);

        _path = new address[](is_wrapped_native ? 2 : 3);
        _path[0] = _token_in;

        if (is_wrapped_native) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(wrappedNative);
            _path[2] = _token_out;
        }
    }
}
