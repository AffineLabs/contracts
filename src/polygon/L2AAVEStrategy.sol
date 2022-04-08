// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ILendingPoolAddressesProvider } from "../interfaces/aave/ILendingPoolAddressesProvider.sol";
import { IAaveIncentivesController } from "../interfaces/aave/IAaveIncentivesController.sol";
import { ILendingPool } from "../interfaces/aave/ILendingPool.sol";
import { IAToken } from "../interfaces/aave/IAToken.sol";

import { BaseVault } from "../BaseVault.sol";
import { BaseStrategy } from "../BaseStrategy.sol";

interface ILendingPoolAddressesProviderRegistry {
    function getAddressesProvidersList() external view returns (address[] memory);
}

contract L2AAVEStrategy is BaseStrategy {
    using SafeTransferLib for ERC20;

    // AAVE protocol contracts
    IAaveIncentivesController public immutable incentivesController;
    ILendingPool public immutable lendingPool;

    // USDC pool reward token is WMATIC
    address public immutable rewardToken;
    address public immutable wrappedNative;

    // Corresponding AAVE token (USDC -> aUSDC)
    IAToken public immutable aToken;

    // Router for swapping reward tokens to `token`
    IUniLikeSwapRouter public immutable router;

    // The mininum amount of token token to trigger position adjustment
    uint256 public minWant = 100;
    uint256 public minRewardToSell = 1e15;

    uint256 public constant MAX_BPS = 1e4;
    uint256 public constant PESSIMISM_FACTOR = 1000;

    constructor(
        BaseVault _vault,
        address _registry,
        address _incentives,
        address _router,
        address _rewardToken,
        address _wrappedNative
    ) {
        vault = _vault;
        token = vault.token();
        address[] memory providers = ILendingPoolAddressesProviderRegistry(_registry).getAddressesProvidersList();
        address pool = ILendingPoolAddressesProvider(providers[providers.length - 1]).getLendingPool();
        lendingPool = ILendingPool(pool);

        address _aToken = lendingPool.getReserveData(address(token)).aTokenAddress;
        aToken = IAToken(_aToken);

        incentivesController = IAaveIncentivesController(_incentives);

        router = IUniLikeSwapRouter(_router);
        rewardToken = _rewardToken;
        wrappedNative = _wrappedNative;

        // approve
        ERC20(_aToken).safeApprove(pool, type(uint256).max);
        token.safeApprove(pool, type(uint256).max);
        ERC20(rewardToken).safeApprove(_router, type(uint256).max);
    }

    /** BALANCES
     **************************************************************************/

    function balanceOfToken() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function balanceOfRewardToken() public view returns (uint256) {
        return ERC20(rewardToken).balanceOf(address(this));
    }

    function balanceOfAToken() public view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /** INVESTMENT
     **************************************************************************/
    function invest(uint256 amount) external override {
        token.transferFrom(msg.sender, address(this), amount);
        _depositWant(amount);
    }

    function _depositWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.deposit(address(token), amount, address(this), 0);
        return amount;
    }

    /** DIVESTMENT
     **************************************************************************/
    function divest(uint256 amount) external override onlyVault returns (uint256) {
        // TODO: take current balance into consideration and only withdraw the amount that you need to
        _claimAndSellRewards();
        uint256 aTokenAmount = balanceOfAToken();
        uint256 withdrawAmount = Math.min(amount, aTokenAmount);

        uint256 withdrawnAmount = _withdrawWant(withdrawAmount);
        token.transfer(address(vault), withdrawnAmount);
        return withdrawnAmount;
    }

    function _withdrawWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.withdraw(address(token), amount, address(this));
        return amount;
    }

    function _claimAndSellRewards() internal {
        incentivesController.claimRewards(getAaveAssets(), type(uint256).max, address(this));

        if (rewardToken != address(token)) {
            uint256 rewardTokenBalance = balanceOfRewardToken();
            if (rewardTokenBalance >= minRewardToSell) {
                _sellRewardTokenForWant(rewardTokenBalance, 0);
            }
        }
    }

    function _sellRewardTokenForWant(uint256 amountIn, uint256 minOut) internal {
        if (amountIn == 0) return;

        router.swapExactTokensForTokens(
            amountIn,
            minOut,
            getTokenOutPathV2(address(rewardToken), address(token)),
            address(this),
            block.timestamp
        );
    }

    /** TVL ESTIMATION
     **************************************************************************/
    function totalLockedValue() public view override returns (uint256) {
        uint256 balanceExcludingRewards = balanceOfToken() + balanceOfAToken();

        // if we don't have a position, don't worry about rewards
        if (balanceExcludingRewards < minWant) {
            return balanceExcludingRewards;
        }

        uint256 rewards = (estimatedRewardsInWant() * (MAX_BPS - PESSIMISM_FACTOR)) / MAX_BPS;

        return balanceExcludingRewards + rewards;
    }

    function estimatedRewardsInWant() public view returns (uint256) {
        uint256 rewardTokenBalance = balanceOfRewardToken();

        uint256 pendingRewards = incentivesController.getRewardsBalance(getAaveAssets(), address(this));

        if (rewardToken == address(token)) {
            return pendingRewards;
        } else {
            return assetToToken(rewardToken, rewardTokenBalance + pendingRewards);
        }
    }

    function assetToToken(address asset, uint256 amountAsset) internal view returns (uint256) {
        if (amountAsset == 0 || address(asset) == address(token)) {
            return amountAsset;
        }

        uint256[] memory amounts = router.getAmountsOut(amountAsset, getTokenOutPathV2(asset, address(token)));

        return amounts[amounts.length - 1];
    }

    function getAaveAssets() internal view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = address(aToken);
    }

    // TODO: is this function needed?

    /// @dev This function will choose  a path of [A, B] if either A or B is WETH (or equivalent on other EVM chains)
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
