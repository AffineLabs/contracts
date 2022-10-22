// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {ICurvePool} from "../interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "../interfaces/convex.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ConvexStrategy is BaseStrategy, AccessControl {
    using SafeTransferLib for ERC20;

    // Asset index of USDC during deposit and withdraw.
    int128 public constant ASSET_INDEX = 1;
    uint256 public constant MIN_TOKEN_AMT = 0.1e18; // 0.1 CRV or CVX
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice The curve pool, e.g. FRAX/USDC. Stableswap pool addresses are different from their lp token addresses
    /// @dev https://curve.readthedocs.io/exchange-deposits.html#curve-stableswap-exchange-deposit-contracts
    ICurvePool public immutable curvePool;
    ERC20 public immutable curveLpToken;

    /// @notice Id of the curve pool (used by convex booster).
    uint256 public immutable convexPid;
    // Convex booster contract address. Used for depositing curve lp tokens.
    IConvexBooster public immutable convexBooster;
    /// @notice BaseRewardPool address
    IConvexRewards public immutable cvxRewarder;

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ERC20 public constant crv = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant cvx = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    bytes32 public constant OWNER = keccak256("OWNER");

    constructor(BaseVault _vault, ICurvePool _curvePool, uint256 _convexPid, IConvexBooster _convexBooster)
        BaseStrategy(_vault)
    {
        curvePool = _curvePool;
        convexPid = _convexPid;
        convexBooster = _convexBooster;

        IConvexBooster.PoolInfo memory poolInfo = convexBooster.poolInfo(convexPid);
        cvxRewarder = IConvexRewards(poolInfo.crvRewards);
        curveLpToken = ERC20(poolInfo.lptoken);

        // For deposing `asset` into curv and depositing curve lp tokens into convex
        asset.safeApprove(address(curvePool), type(uint256).max);
        curveLpToken.safeApprove(address(convexBooster), type(uint256).max);

        // For trading cvx and crv
        crv.safeApprove(address(router), type(uint256).max);
        cvx.safeApprove(address(router), type(uint256).max);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER, msg.sender);
    }

    function deposit(uint256 assets, uint256 minLpTokens) external onlyRole(OWNER) {
        // e.g. in a FRAX-USDC stableswap pool, the 0 index is for FRAX and the index 1 is for USDC.
        uint256[2] memory depositAmounts = [uint256(0), 0];
        depositAmounts[uint256(uint128(ASSET_INDEX))] = assets;
        curvePool.add_liquidity({depositAmounts: depositAmounts, minMintAmount: minLpTokens});
        convexBooster.depositAll(convexPid, true);
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets, 0);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice Withdraw from crv + convex and try to increase balance of `asset` to `assets`.
     * @dev Useful in the case that we want to do multiple withdrawals ahead of a big divestment from the vault. Doing the
     * withdrawals manually (in chunks) will give us less slippage
     */
    function withdrawAssets(uint256 assets, uint256 minAssetsFromLp) external onlyRole(OWNER) {
        _withdraw(assets, minAssetsFromLp);
    }

    function claimRewards() external onlyRole(OWNER) {
        cvxRewarder.getReward();
    }

    function claimAndSellRewards(uint256 minAssetsFromCrv, uint256 minAssetsFromCvx) external onlyRole(OWNER) {
        cvxRewarder.getReward();
        // Sell crv rewards if we have at least MIN_TOKEN_AMT tokens
        // Routing through WETH for high liquidity
        address[] memory crvPath = new address[](3);
        crvPath[0] = address(crv);
        crvPath[1] = WETH;
        crvPath[2] = address(asset);

        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal >= MIN_TOKEN_AMT) {
            router.swapExactTokensForTokens({
                amountIn: crvBal,
                amountOutMin: minAssetsFromCrv,
                path: crvPath,
                to: address(this),
                deadline: block.timestamp
            });
        }

        // Sell cvx rewards if we have at least MIN_TOKEN_AMT tokens
        address[] memory cvxPath = new address[](3);
        cvxPath[0] = address(cvx);
        cvxPath[1] = WETH;
        cvxPath[2] = address(asset);

        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal >= MIN_TOKEN_AMT) {
            router.swapExactTokensForTokens({
                amountIn: cvxBal,
                amountOutMin: minAssetsFromCvx,
                path: cvxPath,
                to: address(this),
                deadline: block.timestamp
            });
        }
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets, uint256 minAssetsFromLp) internal {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[2] memory withdrawAmounts = [uint256(0), 0];
        withdrawAmounts[uint256(uint128(ASSET_INDEX))] = assetsToDivest;

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
        uint256 lpTokenBal = curveLpToken.balanceOf(address(this)) + cvxRewarder.balanceOf(address(this));
        uint256 assetsLp = curvePool.calc_withdraw_one_coin(lpTokenBal, ASSET_INDEX);
        return balanceOfAsset() + assetsLp;
    }
}
