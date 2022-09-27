// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {IUSDCMetaPoolZap} from "../interfaces/IMetaPoolZap.sol";
import {IConvexBooster} from "../interfaces/convex/IConvexBooster.sol";
import {IConvexClaimZap} from "../interfaces/convex/IConvexClaimZap.sol";
import {IConvexCrvRewards} from "../interfaces/convex/IConvexCrvRewards.sol";
import {IUniLikeSwapRouter} from "../interfaces/IUniLikeSwapRouter.sol";

contract ConvexUSDCStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    int128 public constant ASSET_INDEX = 1;
    uint256 public constant CRV_SWAP_THRESHOLD = 10e18; // 10 CRV
    uint256 public constant CVX_SWAP_THRESHOLD = 10e18; // 10 CVX

    IUSDCMetaPoolZap public immutable curveZapper;
    ERC20 public immutable curveLpToken;

    ERC20 public immutable convexPoolCrvRewardsToken;
    uint256 public immutable convexPid;
    IConvexBooster public immutable convexBooster;
    IConvexClaimZap public immutable convexClaimZap;
    IConvexCrvRewards public immutable convexRewardContract;
    address[] public convexRewardContracts;

    IUniLikeSwapRouter public immutable router;
    ERC20 public immutable crv;
    address[] public crvPath = new address[](2);
    ERC20 public immutable cvx;
    address[] public cvxPath = new address[](2);

    constructor(
        BaseVault _vault,
        IUSDCMetaPoolZap _curveZapper,
        uint256 _convexPid,
        IConvexBooster _convexBooster,
        IConvexClaimZap _convexClaimZap,
        IConvexCrvRewards _convexRewardContract,
        IUniLikeSwapRouter _router
    ) BaseStrategy(_vault) {
        curveZapper = _curveZapper;
        curveLpToken = ERC20(curveZapper.lp_token());

        convexPid = _convexPid;
        convexBooster = _convexBooster;
        convexPoolCrvRewardsToken = ERC20(convexBooster.poolInfo(convexPid).crvRewards);
        convexClaimZap = _convexClaimZap;
        convexRewardContract = _convexRewardContract;
        convexRewardContracts.push(address(convexRewardContract));

        router = _router;
        crv = ERC20(convexClaimZap.crv());
        cvx = ERC20(convexClaimZap.cvx());

        crvPath[0] = address(crv);
        crvPath[1] = address(asset);

        cvxPath[0] = address(cvx);
        cvxPath[1] = address(asset);

        asset.safeApprove(address(curveZapper), type(uint256).max);
        curveLpToken.safeApprove(address(convexBooster), type(uint256).max);
        crv.safeApprove(address(convexClaimZap), type(uint256).max);
        cvx.safeApprove(address(convexClaimZap), type(uint256).max);
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
        convexBooster.depositAll(convexPid, true);
    }

    function _deposit(uint256 assets) internal {
        // e.g. in a FRAX-USDC metapool, the 0 index is for FRAX and the index 1 is for USDC.
        uint256[2] memory depositAmounts = [0, assets];
        // TODO: reconsider infinite slippage.
        curveZapper.add_liquidity(depositAmounts, 0);
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice Withdraw from crv + convex and try to increase balance of `asset` to `assets`.
     * @dev Useful in the case that we want to do multiple withdrawals ahead of a big divestment from the vault. Doing the
     * withdrawals manually (in chunks) will give us less slippage
     */
    function withdrawAssets(uint256 assets) external onlyOwner {
        _withdraw(assets);
    }

    function _claimAllRewards() internal {
        address[] memory emptyAddressArray;
        convexClaimZap.claimRewards(
            convexRewardContracts, emptyAddressArray, emptyAddressArray, emptyAddressArray, 0, 0, 0, 0, 0
        );
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets) internal {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        _claimAllRewards();

        // Sell crv rewards if we have at least CRV_SWAP_THRESHOLD tokens
        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal >= CRV_SWAP_THRESHOLD) {
            router.swapExactTokensForTokens(crvBal, 0, crvPath, address(this), block.timestamp);
        }

        // Sell cvx rewards if we have at least CVX_SWAP_THRESHOLD tokens
        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= CVX_SWAP_THRESHOLD) {
            router.swapExactTokensForTokens(cvxBal, 0, cvxPath, address(this), block.timestamp);
        }

        convexRewardContract.withdrawAllAndUnwrap(true);

        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[2] memory withdrawAmounts = [0, assetsToDivest];

        // If the amount  of lp tokens is greater than we have, simply burn the max amount of tokens
        try curveZapper.remove_liquidity_imbalance(withdrawAmounts, curveLpToken.balanceOf(address(this))) {
            // We successfully withdrew `assetsToDivest` and our balance is now `assets`
        } catch (bytes memory) {
            // We didn't have enough lp tokens to withdraw `assetsToDivest`. So we just burn all of our lp shares
            curveZapper.remove_liquidity_one_coin(curveLpToken.balanceOf(address(this)), ASSET_INDEX, 0);
        }

        if (curveLpToken.balanceOf(address(this)) > 0) {
            convexBooster.depositAll(convexPid, true);
        }
    }

    function balanceOfAsset() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function totalLockedValue() external override returns (uint256) {
        _claimAllRewards();

        uint256 assetsFromCrv;
        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal >= CRV_SWAP_THRESHOLD) {
            uint256[] memory amounts = router.getAmountsOut(crvBal, crvPath);
            assetsFromCrv = amounts[amounts.length - 1];
        }

        uint256 assetsFromCvx;
        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= CVX_SWAP_THRESHOLD) {
            uint256[] memory amounts = router.getAmountsOut(cvxBal, cvxPath);
            assetsFromCvx = amounts[amounts.length - 1];
        }

        return balanceOfAsset() + assetsFromCrv + assetsFromCvx
            + curveZapper.calc_withdraw_one_coin(convexPoolCrvRewardsToken.balanceOf(address(this)), ASSET_INDEX);
    }
}
