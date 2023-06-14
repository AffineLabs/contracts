// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";

import {Vault} from "src/vaults/Vault.sol";

contract BeefyStrategy is AccessStrategy {
    using FixedPointMathLib for uint256;

    // curve pool info
    int128 public immutable assetIndex;
    ICurvePool public immutable curvePool;
    I3CrvMetaPoolZap public immutable zapper;

    // beefy vault
    IBeefyVault public immutable beefy;
    // beefy asset pool
    ERC20Upgradeable public immutable bAsset;

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

        bAsset = ERC20Upgradeable(beefy.want());

        require(address(bAsset) == address(curvePool), "BS: want asset mismatch");

        // TODO: approval of taken for zapper, LpToken
    }

    function _afterInvest(uint256 assets) internal override {
        investIntoBeefy(assets, defaultSlippageBps);
    }

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

    function _divest(uint256 assets) internal override returns (uint256) {
        return divestFromBeefy(assets, defaultSlippageBps);
    }

    function divestFromBeefy(uint256 assets, uint256 slippageBps) internal returns (uint256) {
        if (asset.balanceOf(address(this)) > assets) {
            return assets;
        }
        uint256 requiredAssets = assets - asset.balanceOf(address(this));

        uint256[4] memory amounts = [uint256(0), 0, 0, 0];
        amounts[uint256(uint128(assetIndex))] = requiredAssets;

        uint256 lpToken = zapper.calc_token_amount(address(curvePool), amounts, false);

        uint256 lpTokenToWithdraw = lpToken.mulDivDown(MAX_BPS, MAX_BPS - slippageBps);

        withdrawLPTokenFromBeefy(lpTokenToWithdraw);

        // remove liquidity from curve
        removeLiquidityFromCurve(bAsset.balanceOf(address(this)), slippageBps);

        // only withdrawing required assets
        return asset.balanceOf(address(this));
    }

    function removeLiquidityFromCurve(uint256 amount, uint256 slippageBps) internal {
        uint256 withdrawableAssets = zapper.calc_withdraw_one_coin(address(curvePool), amount, assetIndex);

        uint256 minAssets = withdrawableAssets.mulDivDown(MAX_BPS - slippageBps, MAX_BPS);

        zapper.remove_liquidity_one_coin(address(curvePool), bAsset.balanceOf(address(this)), assetIndex, minAssets);
    }

    function withdrawLPTokenFromBeefy(uint256 lpTokenAmount) internal {
        // shares to withdraw
        uint256 beefyShareToWithdraw = lpTokenAmount.divWadUp(beefy.getPricePerFullShare());

        // check for min shares
        beefyShareToWithdraw = Math.min(beefy.balanceOf(address(this)), beefyShareToWithdraw);

        beefy.withdraw(beefyShareToWithdraw);
    }

    function totalLockedValue() external view override returns (uint256) {
        uint256 lpTokenAmount =
            beefy.balanceOf(address(this)).mulWadDown(beefy.getPricePerFullShare()) + bAsset.balanceOf(address(this));
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
        removeLiquidityFromCurve(bAsset.balanceOf(address(this)), slippageBps);
    }
}
