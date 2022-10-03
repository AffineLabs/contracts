// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {ICurveUSDCStableSwapZap} from "../interfaces/curve/ICurveUSDCStableSwapZap.sol";
import {IConvexBooster} from "../interfaces/convex/IConvexBooster.sol";
import {IConvexClaimZap} from "../interfaces/convex/IConvexClaimZap.sol";
import {IConvexCrvRewards} from "../interfaces/convex/IConvexCrvRewards.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ConvexUSDCStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    // Asset index of USDC during deposit and withdraw.
    int128 public constant ASSET_INDEX = 1;
    uint256 public constant CRV_SWAP_THRESHOLD = 1e17; // 0.1 CRV
    uint256 public constant CVX_SWAP_THRESHOLD = 10e18; // 10 CVX

    // https://curve.readthedocs.io/exchange-deposits.html#curve-stableswap-exchange-deposit-contracts
    ICurveUSDCStableSwapZap public immutable curveZapper;
    ERC20 public immutable curveLpToken;

    // Reward token issued by convex
    ERC20 public immutable convexPoolCrvRewardsToken;
    // Pool ID of the convex pool.
    uint256 public immutable convexPid;
    // Convex booster contract address. Used for depositing.
    IConvexBooster public immutable convexBooster;
    // Claim Zap contract. This contract is used for claiming rewards for staking
    // curve LP tokens to convex pools.
    IConvexClaimZap public immutable convexClaimZap;
    // Reward contact address consumed by the convexClaimZap contract.
    IConvexCrvRewards public immutable convexRewardContract;
    address[] public convexRewardContracts;

    IUniswapV2Router02 public immutable router;
    ERC20 public immutable crv;
    ERC20 public immutable cvx;

    constructor(
        BaseVault _vault,
        ICurveUSDCStableSwapZap _curveZapper,
        uint256 _convexPid,
        IConvexBooster _convexBooster,
        IConvexClaimZap _convexClaimZap,
        IConvexCrvRewards _convexRewardContract,
        IUniswapV2Router02 _router
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

        asset.safeApprove(address(curveZapper), type(uint256).max);
        curveLpToken.safeApprove(address(convexBooster), type(uint256).max);
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
        convexBooster.depositAll(convexPid, true);
    }

    function _deposit(uint256 assets) internal {
        // e.g. in a FRAX-USDC stableswap pool, the 0 index is for FRAX and the index 1 is for USDC.
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
        address[] memory crvPath = new address[](2);
        crvPath[0] = address(crv);
        crvPath[1] = address(asset);

        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal >= CRV_SWAP_THRESHOLD) {
            router.swapExactTokensForTokens(crvBal, 0, crvPath, address(this), block.timestamp);
        }

        // Sell cvx rewards if we have at least CVX_SWAP_THRESHOLD tokens
        address[] memory cvxPath = new address[](2);
        cvxPath[0] = address(cvx);
        cvxPath[1] = address(asset);

        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= CVX_SWAP_THRESHOLD) {
            router.swapExactTokensForTokens(cvxBal, 0, cvxPath, address(this), block.timestamp);
        }

        // TODO: Find a way to not withdraw all and depositing back the leftover.
        // Calculate what amount is needed to facilitate the withdrawal of desired amount of
        // assets.
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

    function totalLockedValue() external override returns (uint256) {
        _claimAllRewards();

        uint256 assetsFromCrv;
        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal >= CRV_SWAP_THRESHOLD) {
            address[] memory crvPath = new address[](2);
            crvPath[0] = address(crv);
            crvPath[1] = address(asset);
            uint256[] memory crvAmounts = router.getAmountsOut(crvBal, crvPath);
            assetsFromCrv = crvAmounts[crvAmounts.length - 1];
        }

        uint256 assetsFromCvx;
        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= CVX_SWAP_THRESHOLD) {
            address[] memory cvxPath = new address[](2);
            cvxPath[0] = address(cvx);
            cvxPath[1] = address(asset);
            uint256[] memory cvxAmounts = router.getAmountsOut(cvxBal, cvxPath);
            assetsFromCvx = cvxAmounts[cvxAmounts.length - 1];
        }

        return balanceOfAsset() + assetsFromCrv + assetsFromCvx
            + curveZapper.calc_withdraw_one_coin(convexPoolCrvRewardsToken.balanceOf(address(this)), ASSET_INDEX);
    }
}
