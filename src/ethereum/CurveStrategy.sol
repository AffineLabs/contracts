// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {I3CrvMetaPoolZap} from "../interfaces/IMetaPoolZap.sol";
import {ILiquidityGauge} from "../interfaces/ILiquidityGauge.sol";
import {IUniLikeSwapRouter} from "../interfaces/IUniLikeSwapRouter.sol";

contract CurveStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    I3CrvMetaPoolZap public immutable zapper;
    ERC20 public immutable metaPool;
    /// @notice The index assigned to `asset` in the metapool
    int128 public immutable assetIndex;
    ILiquidityGauge public immutable gauge;

    IUniLikeSwapRouter public immutable router;
    ERC20 public immutable crv;

    constructor(
        BaseVault _vault,
        ERC20 _metaPool,
        I3CrvMetaPoolZap _zapper,
        int128 _assetIndex,
        ILiquidityGauge _gauge,
        IUniLikeSwapRouter _router,
        ERC20 _crv
    ) {
        vault = _vault;
        asset = ERC20(vault.asset());

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

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        // Sell rewards if we have at least 10 CRV tokens
        uint256 crvBal = gauge.claimable_tokens(address(this));

        address[] memory path = new address[](2);
        path[0] = address(crv);
        path[1] = address(asset);

        if (crvBal > 10e18) {
            router.swapExactTokensForTokens(crvBal, 0, path, address(this), block.timestamp);
        }

        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            asset.safeTransfer(address(vault), assets);
            return assets;
        }

        // Only divest the amount that you have to
        uint256 assetsToDivest = assets - currAssets;
        uint256[4] memory withdrawAmounts = [0, 0, assetsToDivest, 0];

        // If the amount  of lp tokens is greater than we have, simply burn the max amount of tokens
        try zapper.remove_liquidity_imbalance(address(metaPool), withdrawAmounts, metaPool.balanceOf(address(this))) {
            // We successfully withdrew `assetsToDivest` and our balance is now `assets`
            asset.safeTransfer(address(vault), assets);
            return assets;
        } catch (bytes memory) {
            // We didn't have enough lp tokens to withdraw `assetsToDivest`. So we just burn all of our lp shares
            zapper.remove_liquidity_one_coin(address(metaPool), metaPool.balanceOf(address(this)), assetIndex, 0);
            uint256 bal = asset.balanceOf(address(this));
            asset.safeTransfer(address(vault), bal);
            return bal;
        }
    }

    function depositInGauge() external onlyOwner {
        gauge.deposit(metaPool.balanceOf(address(this)));
    }

    function balanceOfAsset() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function totalLockedValue() external override returns (uint256) {
        return balanceOfAsset()
            + zapper.calc_withdraw_one_coin(address(metaPool), metaPool.balanceOf(address(this)), assetIndex);
    }
}
