// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {I3CrvMetaPoolZap, ILiquidityGauge, ICurvePool} from "../interfaces/curve.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract CurveStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    I3CrvMetaPoolZap public immutable zapper;
    ERC20 public immutable metaPool;
    /// @notice The index assigned to `asset` in the metapool
    int128 public immutable assetIndex;
    ILiquidityGauge public immutable gauge;

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ERC20 public constant crv = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(BaseVault _vault, ERC20 _metaPool, I3CrvMetaPoolZap _zapper, int128 _assetIndex, ILiquidityGauge _gauge)
        BaseStrategy(_vault)
    {
        metaPool = _metaPool;
        zapper = _zapper;
        assetIndex = _assetIndex;
        gauge = _gauge;

        // mint/burn lp tokens + deposit into gauge
        asset.safeApprove(address(zapper), type(uint256).max);
        metaPool.safeApprove(address(zapper), type(uint256).max);
        metaPool.safeApprove(address(gauge), type(uint256).max);

        // For trading crv
        crv.safeApprove(address(router), type(uint256).max);
    }

    function deposit(uint256 assets, uint256 minLpTokens) external onlyOwner {
        // e.g. in a MIM-3CRV metapool, the 0 index is for MIM and the next three are for the underlying
        // coins of 3CRV
        // In this particular metapool, the 1st, 2nd, and 3rd indices are for DAI, USDC, and USDT
        uint256[4] memory depositAmounts = [0, 0, assets, 0];
        zapper.add_liquidity(address(metaPool), depositAmounts, minLpTokens);
        gauge.deposit(metaPool.balanceOf(address(this)));
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function claimRewards(uint256 minAssetsFromCrv) external onlyOwner {
        gauge.claim_rewards();
        uint256 crvBal = crv.balanceOf(address(this));

        address[] memory crvPath = new address[](3);
        crvPath[0] = address(crv);
        crvPath[1] = WETH;
        crvPath[2] = address(asset);

        if (crvBal > 0.1e18) {
            router.swapExactTokensForTokens({
                amountIn: crvBal,
                amountOutMin: minAssetsFromCrv,
                path: crvPath,
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
        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[4] memory withdrawAmounts = [0, 0, assetsToDivest, 0];

        // price * (num of lp tokens) = dollars.
        uint256 lpTokenBal = metaPool.balanceOf(address(this));
        uint256 price = ICurvePool(address(metaPool)).get_virtual_price(); // 18 decimals
        uint256 dollarsOfLp = price.mulWadDown(lpTokenBal);
        // We assume that the  vault `asset` is $1.00 (i.e. we assume that USDC is 1.00)
        uint256 dollarsOfAssetsToDivest = assetsToDivest * 1e12;

        uint256 maxLpTokensToBurn =
            Math.min(lpTokenBal, lpTokenBal.mulDivDown(dollarsOfAssetsToDivest, dollarsOfLp).mulDivDown(101, 100));
        zapper.remove_liquidity_imbalance(address(metaPool), withdrawAmounts, maxLpTokensToBurn);
    }

    function totalLockedValue() external override returns (uint256) {
        uint256 assetsLp;
        uint256 lpTokenBal = metaPool.balanceOf(address(this)) + gauge.balanceOf(address(this));
        if (lpTokenBal > 100) {
            assetsLp = zapper.calc_withdraw_one_coin(address(metaPool), lpTokenBal, assetIndex);
        }
        return balanceOfAsset() + assetsLp;
    }
}
