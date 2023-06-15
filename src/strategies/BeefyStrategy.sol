// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// import "forge-std/console.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    // beefy asset pool
    IERC20 public immutable bAsset;

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

        // console.log("beefy vault %s", address(beefy));
        // console.log("beefy want %s", address(beefy.want()));

        bAsset = IERC20(beefy.want());

        require(address(bAsset) == address(curvePool), "BS: want asset mismatch");

        bAsset.approve(address(beefy), type(uint256).max);
        // asset.approve(address(curvePool), type(uint256).max);
        asset.approve(address(zapper), type(uint256).max);
        bAsset.approve(address(zapper), type(uint256).max);

        // TODO: // set default slippage
        defaultSlippageBps = 50;
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

        // console.log("balance of curve pool assets ", curvePool.balanceOf(address(this)));
        // remove liquidity from curve
        removeLiquidityFromCurve(bAsset.balanceOf(address(this)), slippageBps);

        // only withdrawing required assets
        return asset.balanceOf(address(this));
    }

    function removeLiquidityFromCurve(uint256 amount, uint256 slippageBps) internal {
        uint256 withdrawableAssets = zapper.calc_withdraw_one_coin(address(curvePool), amount, assetIndex);

        uint256 minAssets = withdrawableAssets.mulDivDown(MAX_BPS - slippageBps, MAX_BPS);
        // console.log(
        //     "withdrawable %s, min assets %s, diff in assets %s",
        //     withdrawableAssets,
        //     minAssets,
        //     withdrawableAssets - minAssets
        // );
        zapper.remove_liquidity_one_coin(address(curvePool), amount, assetIndex, minAssets);
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

        if (lpTokenAmount < 3) {
            // @dev providing values less than 3 incurs evn crash, not returning zero zero
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
        removeLiquidityFromCurve(bAsset.balanceOf(address(this)), slippageBps);
    }
}
