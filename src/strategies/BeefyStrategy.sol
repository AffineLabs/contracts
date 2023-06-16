// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// import "forge-std/console.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";

import {Vault} from "src/vaults/Vault.sol";

contract BeefyStrategy is AccessStrategy {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // curve pool info
    int128 public immutable assetIndex;
    ICurvePool public immutable curvePool;
    I3CrvMetaPoolZap public immutable zapper;

    // beefy vault
    IBeefyVault public immutable beefy;
    // const max bps
    uint256 public constant MAX_BPS = 10_000;
    uint256 public defaultSlippageBps;

    constructor(
        Vault _vault,
        ICurvePool _pool,
        I3CrvMetaPoolZap _zapper,
        int128 _assetIndex,
        IBeefyVault _beefy,
        address[] memory strategists
    ) AccessStrategy(_vault, strategists) {
        assetIndex = _assetIndex;
        curvePool = _pool;
        zapper = _zapper;
        beefy = _beefy;

        require(address(beefy.want()) == address(curvePool), "BS: want asset mismatch");

        curvePool.approve(address(beefy), type(uint256).max);
        asset.approve(address(zapper), type(uint256).max);
        curvePool.approve(address(zapper), type(uint256).max);
    }

    /**
     * @notice utilize the asset in the strategy
     * @param assets total assets to invest
     * @dev it will use default strategy slippage for curve
     */
    function _afterInvest(uint256 assets) internal override {
        investIntoBeefy(assets, defaultSlippageBps);
    }

    /**
     * @notice invest the asset into beefy
     * @param assets amount of asset
     * @param slippageBps slippage for curve pool
     * @dev when calling from vault, strategy uses default slippage
     */
    function investIntoBeefy(uint256 assets, uint256 slippageBps) internal {
        uint256[4] memory amounts = [uint256(0), 0, 0, 0];
        amounts[uint256(uint128(assetIndex))] = assets;

        // calc min lp token to receive with slippage
        uint256 lpToken = zapper.calc_token_amount(address(curvePool), amounts, true);
        uint256 minLpToken = lpToken.mulDivDown(MAX_BPS - slippageBps, MAX_BPS);

        // add liquidity in curve pool
        zapper.add_liquidity(address(curvePool), amounts, minLpToken);

        // deposit lpToken in beefy
        beefy.depositAll();
    }

    /**
     * @notice withdraw assets from beefy and liquidate lpToken to get asset
     * @param assets amount of asset to withdraw
     * @dev will transfer the assets to the vault
     */
    function _divest(uint256 assets) internal override returns (uint256) {
        uint256 amount = divestFromBeefy(assets, defaultSlippageBps);
        uint256 amountToSend = Math.min(assets, amount);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * @notice withdraw shares from beefy and convert it into assets
     * @param assets amount of assets to withdraw
     * @param slippageBps slippage for curve pool
     */
    function divestFromBeefy(uint256 assets, uint256 slippageBps) internal returns (uint256) {
        if (asset.balanceOf(address(this)) > assets) {
            return assets;
        }

        uint256 requiredAssets = assets - asset.balanceOf(address(this));

        uint256[4] memory amounts = [uint256(0), 0, 0, 0];
        amounts[uint256(uint128(assetIndex))] = requiredAssets;

        uint256 requiredLpToken = zapper.calc_token_amount(address(curvePool), amounts, false);
        // need to withdraw more due to slippage
        uint256 lpTokenToWithdraw = requiredLpToken.mulDivDown(MAX_BPS, MAX_BPS - slippageBps);

        withdrawLPTokenFromBeefy(lpTokenToWithdraw);

        // remove liquidity from curve
        // @dev withdraw full amount, so that no curve token left idle.
        removeLiquidityFromCurve(slippageBps);

        // only withdrawing required assets
        return asset.balanceOf(address(this));
    }

    /**
     * @notice convert curve lp token to asset
     * @param slippageBps slippage
     */
    function removeLiquidityFromCurve(uint256 slippageBps) internal {
        uint256 withdrawableAssets =
            zapper.calc_withdraw_one_coin(address(curvePool), curvePool.balanceOf(address(this)), assetIndex);

        uint256 minAssets = withdrawableAssets.mulDivDown(MAX_BPS - slippageBps, MAX_BPS);

        zapper.remove_liquidity_one_coin(address(curvePool), curvePool.balanceOf(address(this)), assetIndex, minAssets);
    }

    /**
     * @notice withdraw token from beefy
     * @param lpTokenAmount amount of token to withdraw
     */
    function withdrawLPTokenFromBeefy(uint256 lpTokenAmount) internal {
        // shares to withdraw
        uint256 beefyShareToWithdraw = lpTokenAmount.divWadUp(beefy.getPricePerFullShare());

        // check for min shares
        beefyShareToWithdraw = Math.min(beefy.balanceOf(address(this)), beefyShareToWithdraw);

        beefy.withdraw(beefyShareToWithdraw);
    }

    function totalLockedValue() external view override returns (uint256) {
        uint256 lpTokenAmount =
            beefy.balanceOf(address(this)).mulWadDown(beefy.getPricePerFullShare()) + curvePool.balanceOf(address(this));

        if (lpTokenAmount < 3) {
            // @dev providing values less than 3 incurs evn crash, not returning zero zero
            // on a 18 decimal place 0,1,2 means nothing
            return asset.balanceOf(address(this));
        }
        return zapper.calc_withdraw_one_coin(address(curvePool), lpTokenAmount, assetIndex)
            + asset.balanceOf(address(this));
    }

    function setDefaultSlippageBps(uint256 slippageBps) external onlyGovernance {
        defaultSlippageBps = slippageBps;
    }

    function investAssets(uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        investIntoBeefy(asset.balanceOf(address(this)), slippageBps);
    }

    function divestAssets(uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        beefy.withdrawAll();
        removeLiquidityFromCurve(slippageBps);
    }
}
