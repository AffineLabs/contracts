// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {I3CrvMetaPoolZap, ILiquidityGauge, ICurvePool, IMinter} from "../interfaces/curve.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract CurveStrategy is BaseStrategy, AccessControl {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    I3CrvMetaPoolZap public immutable zapper;
    ERC20 public immutable metaPool;
    /// @notice The index assigned to `asset` in the metapool
    int128 public immutable assetIndex;
    ILiquidityGauge public immutable gauge;
    IMinter public constant MINTER = IMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    /**
     * @notice The minimum amount of lp tokens to count towards tvl or be liquidated during withdrawals.
     * @dev `calc_withdraw_one_coin` and `remove_liquidity_one_coin` may fail when using amounts smaller than this.
     */
    uint256 constant MIN_LP_AMOUNT = 100;

    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Role with authority to manage strategies.
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

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

        // For trading CRV
        CRV.safeApprove(address(ROUTER), type(uint256).max);

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, vault.governance());
        _grantRole(STRATEGIST, vault.governance());
    }

    function deposit(uint256 assets, uint256 minLpTokens) external onlyRole(STRATEGIST) {
        // e.g. in a MIM-3CRV metapool, the 0 index is for MIM and the next three are for the underlying
        // coins of 3CRV
        // In this particular metapool, the 1st, 2nd, and 3rd indices are for DAI, USDC, and USDT
        uint256[4] memory depositAmounts = [uint256(0), 0, 0, 0];
        depositAmounts[uint256(uint128(assetIndex))] = assets;
        zapper.add_liquidity(address(metaPool), depositAmounts, minLpTokens);
        gauge.deposit(metaPool.balanceOf(address(this)));
    }

    function _divest(uint256 assets) internal override returns (uint256) {
        _withdraw(assets);

        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), assets);
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function claimRewards(uint256 minAssetsFromCrv) external onlyRole(STRATEGIST) {
        gauge.claim_rewards();
        MINTER.mint(address(gauge));
        uint256 crvBal = CRV.balanceOf(address(this));

        address[] memory crvPath = new address[](3);
        crvPath[0] = address(CRV);
        crvPath[1] = WETH;
        crvPath[2] = address(asset);

        if (crvBal > 0.1e18) {
            ROUTER.swapExactTokensForTokens({
                amountIn: crvBal,
                amountOutMin: minAssetsFromCrv,
                path: crvPath,
                to: address(this),
                deadline: block.timestamp
            });
        }
    }

    function withdrawAssets(uint256 assets) external onlyRole(STRATEGIST) {
        _withdraw(assets);
    }

    /// @notice Try to increase balance of `asset` to `assets`.
    function _withdraw(uint256 assets) internal {
        uint256 currAssets = asset.balanceOf(address(this));
        if (currAssets >= assets) {
            return;
        }

        // price * (num of lp tokens) = dollars
        uint256 currLpBal = metaPool.balanceOf(address(this));
        uint256 lpTokenBal = currLpBal + gauge.balanceOf(address(this));
        uint256 price = ICurvePool(address(metaPool)).get_virtual_price(); // 18 decimals
        uint256 dollarsOfLp = lpTokenBal.mulWadDown(price);

        // Get the amount of dollars to remove from vault, and the equivalent amount of lp token.
        // We assume that the  vault `asset` is $1.00 (i.e. we assume that USDC is 1.00). Convert to 18 decimals.
        uint256 dollarsOfAssetsToDivest =
            Math.min(_giveDecimals(assets - currAssets, asset.decimals(), 18), dollarsOfLp);
        uint256 lpTokensToDivest = dollarsOfAssetsToDivest.divWadDown(price);

        // Minimum amount of dollars received is 99% of dollar value of lp shares (trading fees, slippage)
        // Convert back to `asset` decimals.
        uint256 minAssetsReceived = _giveDecimals(dollarsOfAssetsToDivest.mulDivDown(99, 100), 18, asset.decimals());
        // Increase the cap on lp tokens by 1% to account for curve's trading fees
        uint256 maxLpTokensToBurn = Math.min(lpTokenBal, lpTokensToDivest.mulDivDown(101, 100));
        if (maxLpTokensToBurn < MIN_LP_AMOUNT) return;

        // Withdraw from gauge if needed to get correct amount of lp tokens
        if (maxLpTokensToBurn > currLpBal) {
            (bool success1,) =
                address(gauge).call(abi.encodeCall(ILiquidityGauge.withdraw, (maxLpTokensToBurn - currLpBal)));
            require(success1, "Crv: gauge withdraw");
        }

        zapper.remove_liquidity_one_coin(address(metaPool), maxLpTokensToBurn, assetIndex, minAssetsReceived);
    }

    function totalLockedValue() external override returns (uint256) {
        uint256 assetsLp;
        uint256 lpTokenBal = metaPool.balanceOf(address(this)) + gauge.balanceOf(address(this));
        if (lpTokenBal > MIN_LP_AMOUNT) {
            assetsLp = zapper.calc_withdraw_one_coin(address(metaPool), lpTokenBal, assetIndex);
        }
        return balanceOfAsset() + assetsLp;
    }

    function _giveDecimals(uint256 number, uint256 inDecimals, uint256 outDecimals) internal pure returns (uint256) {
        if (inDecimals > outDecimals) {
            number = number / (10 ** (inDecimals - outDecimals));
        }
        if (inDecimals < outDecimals) {
            number = number * (10 ** (outDecimals - inDecimals));
        }
        return number;
    }
}
