// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {ICurvePool} from "../interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "../interfaces/convex.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ConvexStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    // Asset index of USDC during deposit and withdraw.
    int128 public constant ASSET_INDEX = 1;
    uint256 public constant CRV_SWAP_THRESHOLD = 5e18; // 1 CRV
    uint256 public constant CVX_SWAP_THRESHOLD = 1e18; // 1 CVX
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // https://curve.readthedocs.io/exchange-deposits.html#curve-stableswap-exchange-deposit-contracts
    ICurvePool public immutable curvePool;
    ERC20 public immutable curveLpToken;

    /// @notice Id of the curve pool (used by convex booster).
    uint256 public immutable convexPid;
    // Convex booster contract address. Used for depositing curve lp tokens.
    IConvexBooster public immutable convexBooster;
    /// @notice BaseRewardPool address
    IConvexRewards public immutable cvxRewarder;

    IUniswapV2Router02 public immutable router;
    ERC20 public immutable crv;
    ERC20 public immutable cvx;

    constructor(
        BaseVault _vault,
        ICurvePool _curvePool,
        uint256 _convexPid,
        IConvexBooster _convexBooster,
        ERC20 _cvx,
        IUniswapV2Router02 _router
    ) BaseStrategy(_vault) {
        curvePool = _curvePool;
        convexPid = _convexPid;
        convexBooster = _convexBooster;

        IConvexBooster.PoolInfo memory poolInfo = convexBooster.poolInfo(convexPid);
        cvxRewarder = IConvexRewards(poolInfo.crvRewards);
        curveLpToken = ERC20(poolInfo.lptoken);

        router = _router;
        crv = ERC20(convexBooster.crv());
        cvx = _cvx;

        // For deposing `asset` into curv and depositing curve lp tokens into convex
        asset.safeApprove(address(curvePool), type(uint256).max);
        curveLpToken.safeApprove(address(convexBooster), type(uint256).max);

        // For trading cvx and crv
        crv.safeApprove(address(router), type(uint256).max);
        cvx.safeApprove(address(router), type(uint256).max);
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function deposit(uint256 assets, uint256 minLpTokens) external onlyOwner {
        // e.g. in a FRAX-USDC stableswap pool, the 0 index is for FRAX and the index 1 is for USDC.
        uint256[2] memory depositAmounts = [0, assets];
        curvePool.add_liquidity({depositAmounts: depositAmounts, minMintAmount: minLpTokens});
        convexBooster.depositAll(convexPid, true);
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets, 0, 0, 0);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice Withdraw from crv + convex and try to increase balance of `asset` to `assets`.
     * @dev Useful in the case that we want to do multiple withdrawals ahead of a big divestment from the vault. Doing the
     * withdrawals manually (in chunks) will give us less slippage
     */
    function withdrawAssets(uint256 assets, uint256 minAssetsFromCrv, uint256 minAssetsFromCvx, uint256 minAssetsFromLp)
        external
        onlyOwner
    {
        _withdraw(assets, minAssetsFromCrv, minAssetsFromCvx, minAssetsFromLp);
    }

    function _claimAllRewards() internal {
        cvxRewarder.getReward();
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets, uint256 minAssetsFromCrv, uint256 minAssetsFromCvx, uint256 minAssetsFromLp)
        internal
    {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        _claimAllRewards();

        // Sell crv rewards if we have at least CRV_SWAP_THRESHOLD tokens
        // Routing through WETH for high liquidity
        address[] memory crvPath = new address[](3);
        crvPath[0] = address(crv);
        crvPath[1] = WETH;
        crvPath[2] = address(asset);

        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal >= CRV_SWAP_THRESHOLD) {
            router.swapExactTokensForTokens({
                amountIn: crvBal,
                amountOutMin: minAssetsFromCrv,
                path: crvPath,
                to: address(this),
                deadline: block.timestamp
            });
        }

        // Sell cvx rewards if we have at least CVX_SWAP_THRESHOLD tokens
        address[] memory cvxPath = new address[](3);
        cvxPath[0] = address(cvx);
        cvxPath[1] = WETH;
        cvxPath[2] = address(asset);

        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= CVX_SWAP_THRESHOLD) {
            router.swapExactTokensForTokens({
                amountIn: cvxBal,
                amountOutMin: minAssetsFromCvx,
                path: cvxPath,
                to: address(this),
                deadline: block.timestamp
            });
        }
        currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[2] memory withdrawAmounts = [0, assetsToDivest];

        // TODO: Find a way to not withdraw all curve lp tokens from convex
        cvxRewarder.withdrawAllAndUnwrap(true);

        // If the amount of lp tokens is greater than we have, simply burn the max amount of tokens
        try curvePool.remove_liquidity_imbalance(withdrawAmounts, type(uint256).max) {
            // We successfully withdrew `assetsToDivest` and our balance is now `assets`
        } catch (bytes memory) {
            // We didn't have enough lp tokens to withdraw `assetsToDivest`. So we just burn all of our lp shares
            curvePool.remove_liquidity_one_coin(curveLpToken.balanceOf(address(this)), ASSET_INDEX, minAssetsFromLp);
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
            address[] memory crvPath = new address[](3);
            crvPath[0] = address(crv);
            crvPath[1] = WETH;
            crvPath[2] = address(asset);
            uint256[] memory crvAmounts = router.getAmountsOut(crvBal, crvPath);
            assetsFromCrv = crvAmounts[crvAmounts.length - 1];
        }

        uint256 assetsFromCvx;
        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= CVX_SWAP_THRESHOLD) {
            address[] memory cvxPath = new address[](3);
            cvxPath[0] = address(cvx);
            cvxPath[1] = WETH;
            cvxPath[2] = address(asset);
            uint256[] memory cvxAmounts = router.getAmountsOut(cvxBal, cvxPath);
            assetsFromCvx = cvxAmounts[cvxAmounts.length - 1];
        }

        return balanceOfAsset() + assetsFromCrv + assetsFromCvx
            + curvePool.calc_withdraw_one_coin(cvxRewarder.balanceOf(address(this)), ASSET_INDEX);
    }
}
