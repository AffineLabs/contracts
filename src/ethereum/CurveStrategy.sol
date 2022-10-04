// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {I3CrvMetaPoolZap} from "../interfaces/IMetaPoolZap.sol";
import {ILiquidityGauge} from "../interfaces/ILiquidityGauge.sol";
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
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
    }

    function _deposit(uint256 assets) internal {
        // e.g. in a MIM-3CRV metapool, the 0 index is for MIM and the next three are for the underlying
        // coins of 3CRV
        // In this particular metapool, the 1st, 2nd, and 3rd indices are for DAI, USDC, and USDT
        uint256[4] memory depositAmounts = [0, 0, assets, 0];
        // Infinite slippage is probably bad
        zapper.add_liquidity(address(metaPool), depositAmounts, 0);
    }

    function depositInGauge() external onlyOwner {
        gauge.deposit(metaPool.balanceOf(address(this)));
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        _withdraw(assets);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice Withdraw from crv and try to increase balance of `asset` to `assets`.
     * @dev Useful in the case that we want to do multiple withdrawals ahead of a big divestment from the vault. Doing the
     * withdrawals manually (in chunks) will give us less slippage
     */
    function withdrawAssets(uint256 assets) external onlyOwner {
        _withdraw(assets);
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets) internal {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // Sell rewards if we have at least 10 CRV tokens
        uint256 crvBal = gauge.claimable_tokens(address(this));

        address[] memory path = new address[](2);
        path[0] = address(crv);
        path[1] = address(asset);

        if (crvBal > 10e18) {
            router.swapExactTokensForTokens(crvBal, 0, path, address(this), block.timestamp);
        }

        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[4] memory withdrawAmounts = [0, 0, assetsToDivest, 0];

        // If the amount  of lp tokens is greater than we have, simply burn the max amount of tokens
        try zapper.remove_liquidity_imbalance(address(metaPool), withdrawAmounts, metaPool.balanceOf(address(this))) {
            // We successfully withdrew `assetsToDivest` and our balance is now `assets`
        } catch (bytes memory) {
            // We didn't have enough lp tokens to withdraw `assetsToDivest`. So we just burn all of our lp shares
            zapper.remove_liquidity_one_coin(address(metaPool), metaPool.balanceOf(address(this)), assetIndex, 0);
        }
    }

    function totalLockedValue() external override returns (uint256) {
        // Get amount of `asset` we would get if we sold all of our curve
        uint256 crvBal = gauge.claimable_tokens(address(this));

        uint256 assetsFromCrv;
        if (crvBal > 0) {
            address[] memory path = new address[](2);
            path[0] = address(crv);
            path[1] = address(asset);

            uint256[] memory amounts = router.getAmountsOut(crvBal, path);
            assetsFromCrv = amounts[amounts.length - 1];
        }

        return balanceOfAsset() + assetsFromCrv
            + zapper.calc_withdraw_one_coin(address(metaPool), metaPool.balanceOf(address(this)), assetIndex);
    }
}
