// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {I3CrvMetaPoolZap} from "../interfaces/IMetaPoolZap.sol";
import {ILiquidityGauge} from "../interfaces/ILiquidityGauge.sol";

contract CurveStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    I3CrvMetaPoolZap public immutable zapper;
    ERC20 public immutable metaPool;
    /// @notice The index assigned to `asset` in the metapool
    int128 public immutable assetIndex;
    ILiquidityGauge public immutable gauge;

    constructor(
        BaseVault _vault,
        ERC20 _metaPool,
        I3CrvMetaPoolZap _zapper,
        int128 _assetIndex,
        ILiquidityGauge _gauge
    ) {
        vault = _vault;
        asset = ERC20(vault.asset());

        metaPool = _metaPool;
        zapper = _zapper;
        assetIndex = _assetIndex;
        gauge = _gauge;

        asset.safeApprove(address(zapper), type(uint256).max);
        metaPool.safeApprove(address(zapper), type(uint256).max);
        metaPool.safeApprove(address(gauge), type(uint256).max);
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
    }

    function _deposit(uint256 assets) internal {
        // e.g. in a MIM-3CRV metapool, the first index is for MIM and the next three are for the underlying
        // coins of 3CRV
        // In this particular metapool, the 1st, 2nd, and 3rd indices are for DAI, USDC, and USDT
        uint256[4] memory depositAmounts = [0, 0, assets, 0];
        // Infinite slippage is probably bad
        zapper.add_liquidity(address(metaPool), depositAmounts, 0);
    }

    function divest(uint256 assets) external override onlyVault returns (uint256) {
        zapper.remove_liquidity_one_coin(address(metaPool), metaPool.balanceOf(address(this)), assetIndex, 0);
        asset.safeTransfer(address(vault), assets);
        return assets;
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
