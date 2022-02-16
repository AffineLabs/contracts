// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { SafeERC20, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseStrategy } from "../BaseStrategy.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { ICToken } from "../interfaces/compound/ICToken.sol";
import { IComptroller } from "../interfaces/compound/IComptroller.sol";

import { BaseVault } from "../BaseVault.sol";
import { Strategy } from "../Strategy.sol";

contract L1CompoundStrategy is Strategy {
    using SafeERC20 for IERC20;
    using Address for address;

    // Compund protocol contracts
    IComptroller public immutable comptroller;
    // Corresponding Compund token (USDC -> cUSDC)
    ICToken public immutable cToken;

    // Comp token
    address public immutable rewardToken;
    // WETH
    address public immutable wrappedNative;

    // Router for swapping reward tokens to `token`
    IUniLikeSwapRouter public immutable router;

    // The mininum amount of token token to trigger position adjustment
    uint256 public minWant = 100;
    uint256 public minRewardToSell = 1e15;

    uint256 public constant MAX_BPS = 1e4;
    uint256 public constant PESSIMISM_FACTOR = 1000;

    constructor(
        BaseVault _vault,
        ICToken _cToken,
        IComptroller _comptroller,
        IUniLikeSwapRouter _router,
        address _rewardToken,
        address _wrappedNative
    ) {
        vault = _vault;
        token = vault.token();
        cToken = _cToken;
        comptroller = _comptroller;

        router = _router;
        rewardToken = _rewardToken;
        wrappedNative = _wrappedNative;
        // Approve transfer on the cToken contract
        token.approve(address(cToken), type(uint256).max);
    }

    /** AUTHENTICATION
     **************************************************************************/
    BaseVault public vault;
    modifier onlyVault() {
        require(msg.sender == address(vault), "ONLY_VAULT");
        _;
    }

    /** BALANCES
     **************************************************************************/

    function balanceOfToken() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function balanceOfRewardToken() public view returns (uint256) {
        return IERC20(rewardToken).balanceOf(address(this));
    }

    function balanceOfCToken() public view returns (uint256) {
        return cToken.balanceOf(address(this));
    }

    /** INVESTMENT
     **************************************************************************/
    function invest(uint256 amount) external override {
        token.transferFrom(msg.sender, address(this), amount);
        _depositWant(amount);
    }

    function _depositWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        require(cToken.mint(amount) == 0, "_depositWant(): minting cToken failed.");
        return amount;
    }

    /** DIVESTMENT
     **************************************************************************/
    function divest(uint256 amount) external override onlyVault {
        // TODO: take current balance into consideration and only withdraw the amount that you need to
        _claimAndSellRewards();
        uint256 cTokenAmount = balanceOfCToken();
        uint256 withdrawAmount = Math.min(amount, cTokenAmount);

        uint256 withdrawnAmount = _withdrawWant(withdrawAmount);
        token.transfer(address(vault), withdrawnAmount);
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

    function _claimAndSellRewards() internal {
        // TODO: Check why claming comp fails in unit tests.
        // comptroller.claimComp(address(this));
        if (rewardToken != address(token)) {
            uint256 rewardTokenBalance = balanceOfRewardToken();
            if (rewardTokenBalance >= minRewardToSell) {
                _sellRewardTokenForWant(rewardTokenBalance, 0);
            }
        }
        return;
    }

    function _sellRewardTokenForWant(uint256 amountIn, uint256 minOut) internal {
        if (amountIn == 0) {
            return;
        }

        router.swapExactTokensForTokens(
            amountIn,
            minOut,
            getTokenOutPathV2(address(rewardToken), address(token)),
            address(this),
            block.timestamp
        );
    }

    function estimatedTotalAssets() public view returns (uint256) {
        uint256 balanceExcludingRewards = balanceOfToken() + balanceOfCToken();

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

        if (rewardToken == address(token)) {
            return rewardTokenBalance + pendingRewards;
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
