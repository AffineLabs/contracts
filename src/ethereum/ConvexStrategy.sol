// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {ICurvePool} from "../interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "../interfaces/convex.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract ConvexStrategy is BaseStrategy, AccessControl {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

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

    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);


    /// @notice Role with authority to manage strategies.
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

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

        // For trading CVX and CRV
        CRV.safeApprove(address(ROUTER), type(uint256).max);
        CVX.safeApprove(address(ROUTER), type(uint256).max);

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, vault.governance());
        _grantRole(STRATEGIST, vault.governance());
    }

    function deposit(uint256 assets, uint256 minLpTokens) external onlyRole(STRATEGIST) {
        // e.g. in a FRAX-USDC stableswap pool, the 0 index is for FRAX and the index 1 is for USDC.
        uint256[2] memory depositAmounts = [uint256(0), 0];
        depositAmounts[uint256(uint128(ASSET_INDEX))] = assets;
        curvePool.add_liquidity({depositAmounts: depositAmounts, minMintAmount: minLpTokens});
        convexBooster.depositAll(convexPid, true);
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice Withdraw from CRV + convex and try to increase balance of `asset` to `assets`.
     * @dev Useful in the case that we want to do multiple withdrawals ahead of a big divestment from the vault. Doing the
     * withdrawals manually (in chunks) will give us less slippage
     */
    function withdrawAssets(uint256 assets) external onlyRole(STRATEGIST) {
        _withdraw(assets);
    }

    function claimRewards() external onlyRole(STRATEGIST) {
        cvxRewarder.getReward();
    }

    function claimAndSellRewards(uint256 minAssetsFromCrv, uint256 minAssetsFromCvx)
        external
        onlyRole(STRATEGIST)
    {
        cvxRewarder.getReward();
        // Sell CRV rewards if we have at least MIN_TOKEN_AMT tokens
        // Routing through WETH for high liquidity
        address[] memory crvPath = new address[](3);
        crvPath[0] = address(CRV);
        crvPath[1] = WETH;
        crvPath[2] = address(asset);

        uint256 crvBal = CRV.balanceOf(address(this));
        if (crvBal >= MIN_TOKEN_AMT) {
            ROUTER.swapExactTokensForTokens({
                amountIn: crvBal,
                amountOutMin: minAssetsFromCrv,
                path: crvPath,
                to: address(this),
                deadline: block.timestamp
            });
        }

        // Sell CVX rewards if we have at least MIN_TOKEN_AMT tokens
        address[] memory cvxPath = new address[](3);
        cvxPath[0] = address(CVX);
        cvxPath[1] = WETH;
        cvxPath[2] = address(asset);

        uint256 cvxBal = CVX.balanceOf(address(this));
        if (cvxBal >= MIN_TOKEN_AMT) {
            ROUTER.swapExactTokensForTokens({
                amountIn: cvxBal,
                amountOutMin: minAssetsFromCvx,
                path: cvxPath,
                to: address(this),
                deadline: block.timestamp
            });
        }
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets) internal {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // price * (num of lp tokens) = dollars
        uint256 currLpBal = curveLpToken.balanceOf(address(this));
        uint256 lpTokenBal = currLpBal + cvxRewarder.balanceOf(address(this));
        uint256 price = curvePool.get_virtual_price(); // 18 decimals
        uint256 dollarsOfLp = lpTokenBal.mulWadDown(price);

        // Get the amount of dollars to remove from vault, and the equivalent amount of lp token.
        // We assume that the  vault `asset` is $1.00 (i.e. we assume that USDC is 1.00). Convert to 18 decimals.
        uint256 dollarsOfAssetsToDivest = Math.min((assets - currAssets) * 1e12, dollarsOfLp);
        uint256 lpTokensToDivest = dollarsOfAssetsToDivest.divWadDown(price);

        // Minimum amount of dollars received is 99% of dollar value of lp shares (trading fees, slippage)
        // Convert back to `asset` decimals.
        uint256 minAssetsReceived = dollarsOfAssetsToDivest.mulDivDown(99, 100) / 1e12;
        // Increase the cap on lp tokens by 1% to account for curve's trading fees
        uint256 maxLpTokensToBurn = Math.min(lpTokenBal, lpTokensToDivest.mulDivDown(101, 100));

        // Withdraw from CVX rewarder contract if needed to get correct amount of lp tokens
        if (maxLpTokensToBurn > currLpBal) {
            cvxRewarder.withdrawAndUnwrap(maxLpTokensToBurn - currLpBal, true);
        }

        curvePool.remove_liquidity_one_coin(curveLpToken.balanceOf(address(this)), ASSET_INDEX, minAssetsReceived);
    }

    function totalLockedValue() external override returns (uint256) {
        uint256 lpTokenBal = curveLpToken.balanceOf(address(this)) + cvxRewarder.balanceOf(address(this));
        uint256 assetsLp = curvePool.calc_withdraw_one_coin(lpTokenBal, ASSET_INDEX);
        return balanceOfAsset() + assetsLp;
    }
}
