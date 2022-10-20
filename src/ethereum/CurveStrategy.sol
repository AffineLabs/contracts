// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {I3CrvMetaPoolZap, ILiquidityGauge} from "../interfaces/curve.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract CurveStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    I3CrvMetaPoolZap public immutable zapper;
    ERC20 public immutable metaPool;
    /// @notice The index assigned to `asset` in the metapool
    int128 public immutable assetIndex;
    ILiquidityGauge public immutable gauge;

    IUniswapV2Router02 public immutable router;
    ERC20 public immutable crv;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(
        BaseVault _vault,
        ERC20 _metaPool,
        I3CrvMetaPoolZap _zapper,
        int128 _assetIndex,
        ILiquidityGauge _gauge,
        IUniswapV2Router02 _router,
        ERC20 _crv
    ) BaseStrategy(_vault) {
        metaPool = _metaPool;
        zapper = _zapper;
        assetIndex = _assetIndex;
        gauge = _gauge;
        router = _router;
        crv = _crv;

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
    }

    function depositInGauge() external onlyOwner {
        gauge.deposit(metaPool.balanceOf(address(this)));
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets, 0, 0);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice Withdraw from crv and try to increase balance of `asset` to `assets`.
     * @dev Useful in the case that we want to do multiple withdrawals ahead of a big divestment from the vault. Doing the
     * withdrawals manually (in chunks) will give us less slippage
     */
    function withdrawAssets(uint256 assets, uint256 minAssetsFromCrv, uint256 minAssetsFromLp) external onlyOwner {
        _withdraw(assets, minAssetsFromCrv, minAssetsFromLp);
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets, uint256 minAssetsFromCrv, uint256 minAssetsFromLp) internal {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // Sell rewards if we have at least 10 CRV tokens
        gauge.claim_rewards();
        uint256 crvBal = crv.balanceOf(address(this));

        address[] memory crvPath = new address[](3);
        crvPath[0] = address(crv);
        crvPath[1] = WETH;
        crvPath[2] = address(asset);

        if (crvBal > 10e18) {
            router.swapExactTokensForTokens(crvBal, minAssetsFromCrv, crvPath, address(this), block.timestamp);
        }

        currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[4] memory withdrawAmounts = [0, 0, assetsToDivest, 0];

        // If the amount  of lp tokens is greater than we have, simply burn the max amount of tokens
        try zapper.remove_liquidity_imbalance(address(metaPool), withdrawAmounts, type(uint256).max) {
            // We successfully withdrew `assetsToDivest` and our balance is now `assets`
        } catch (bytes memory) {
            // We didn't have enough lp tokens to withdraw `assetsToDivest`. So we just burn all of our lp shares
            zapper.remove_liquidity_one_coin(
                address(metaPool), metaPool.balanceOf(address(this)), assetIndex, minAssetsFromLp
            );
        }
    }

    function totalLockedValue() external override returns (uint256) {
        // Get amount of `asset` we would get if we sold all of our curve
        uint256 crvBal = gauge.claimable_tokens(address(this));

        uint256 assetsFromCrv;
        if (crvBal > 0) {
            address[] memory crvPath = new address[](3);
            crvPath[0] = address(crv);
            crvPath[1] = WETH;
            crvPath[2] = address(asset);

            uint256[] memory amounts = router.getAmountsOut(crvBal, crvPath);
            assetsFromCrv = amounts[amounts.length - 1];
        }

        return balanceOfAsset() + assetsFromCrv
            + zapper.calc_withdraw_one_coin(address(metaPool), metaPool.balanceOf(address(this)), assetIndex);
    }
}
