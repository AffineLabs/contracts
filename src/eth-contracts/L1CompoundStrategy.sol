// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { BaseStrategy } from "../BaseStrategy.sol";

import { SafeERC20, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface ICToken is IERC20 {
    function mint(uint256 mintAmount) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function balanceOfUnderlying(address account) external returns (uint256);
}

interface Comptroller {
    // Claim all the COMP accrued by holder in specific markets
    function claimComp(address holder, ICToken[] memory cTokens) external;
    function compAccrued(address holder) external view returns (uint256);
}

contract L1CompundStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    // Compund protocol contracts
    Comptroller public immutable comptroller;
    // Corresponding Compund token (USDC -> cUSDC)
    ICToken public immutable cToken;

    // Comp token
    address public immutable rewardToken;
    // WETH
    address public immutable wrappedNative;

    // Router for swapping reward tokens to `want`
    IUniLikeSwapRouter public immutable router;

    // The mininum amount of want token to trigger position adjustment
    uint256 public minWant = 100;
    uint256 public minRewardToSell = 1e15;

    uint256 public constant MAX_BPS = 1e4;
    uint256 public constant PESSIMISM_FACTOR = 1000;

    constructor(
        address _vault,
        address _cToken,
        address _comptroller, 
        address _router,
        address _rewardToken,
        address _wrappedNative
    ) BaseStrategy(_vault) {
        cToken = ICToken(_cToken);
        comptroller = Comptroller(_comptroller);

        router = IUniLikeSwapRouter(_router);
        rewardToken = _rewardToken;
        wrappedNative = _wrappedNative;
    }

    function name() external pure override returns (string memory) {
        return "L1CompundStrategy";
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
        uint256 totalAssets = balanceOfWant() + balanceOfCToken();

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

    function nativeToWant(uint256 _amtInWei) public view override returns (uint256) {
        return tokenToWant(wrappedNative, _amtInWei);
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 balanceExcludingRewards = balanceOfWant() + balanceOfCToken();

        // if we don't have a position, don't worry about rewards
        if (balanceExcludingRewards < minWant) {
            return balanceExcludingRewards;
        }

        uint256 rewards = (estimatedRewardsInWant() * (MAX_BPS - PESSIMISM_FACTOR)) / MAX_BPS;

        return balanceExcludingRewards + rewards;
    }

    function estimatedRewardsInWant() public view returns (uint256) {
        uint256 rewardTokenBalance = balanceOfRewardToken();

        uint256 pendingRewards = comptroller.compAccrued(address(this));

        if (rewardToken == address(want)) {
            return rewardTokenBalance + pendingRewards;
        } else {
            return tokenToWant(rewardToken, rewardTokenBalance + pendingRewards);
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

    function balanceOfCToken() internal view returns (uint256) {
        return cToken.balanceOf(address(this));
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
        // Approve transfer on the cToken contract
        want.approve(address(cToken), amount);
        // Mint cToken
        require(cToken.mint(amount) == 0, "_depositWant(): minting cToken failed.");
        return amount;
    }

    function _withdrawWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        uint256 balanceOfUnderlying = cToken.balanceOfUnderlying(address(this));
        if (amount > balanceOfUnderlying) {
            amount = balanceOfUnderlying;
        }
        cToken.redeemUnderlying(amount);
        return amount;
    }

    function _freeFunds(uint256 amountToFree) internal returns (uint256) {
        if (amountToFree == 0) return 0;

        uint256 cTokenAmount = balanceOfCToken();
        uint256 withdrawAmount = Math.min(amountToFree, cTokenAmount);

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
        // Only claim comp for cUSDC market.
        comptroller.claimComp(address(this), getCompundAssets());
        if (rewardToken != address(want)) {
            uint256 rewardTokenBalance = balanceOfRewardToken();
            if (rewardTokenBalance >= minRewardToSell) {
                _sellRewardTokenForWant(rewardTokenBalance, 0);
            }
        }

        return;
    }

    function getCompundAssets() internal view returns (ICToken[] memory assets) {
        assets = new ICToken[](1);
        assets[0] = cToken;
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
