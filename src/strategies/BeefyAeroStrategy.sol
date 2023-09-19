// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {IAeroRouter, IAeroPool} from "src/interfaces/aerodrome.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";

import {AffineVault} from "src/vaults/Vault.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";

contract BeefyAeroStrategy is AccessStrategy {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // beefy vault
    IBeefyVault public immutable beefy;
    // const max bps
    uint256 public constant MAX_BPS = 10_000;
    uint256 public defaultSlippageBps;

    ERC20 public immutable token0;
    ERC20 public immutable token1;

    IAeroRouter public immutable aeroRouter;
    IAeroPool public immutable lpToken;
    address public immutable factory;

    constructor(
        AffineVault _vault,
        IBeefyVault _beefy,
        IAeroRouter _router,
        ERC20 _token1,
        address[] memory strategists
    ) AccessStrategy(_vault, strategists) {
        beefy = _beefy;
        token0 = asset;
        token1 = _token1;

        aeroRouter = _router;

        factory = aeroRouter.defaultFactory();
        lpToken = IAeroPool(aeroRouter.poolFor(address(token0), address(token1), false, factory));

        require(address(beefy.want()) == address(lpToken), "BAS: Invalid beefy vault asset.");

        // approve assets to use in aerodrome router
        token0.approve(address(aeroRouter), type(uint256).max);
        token1.approve(address(aeroRouter), type(uint256).max);

        // approve lp token for pearlRouter and beefy vault
        lpToken.approve(address(aeroRouter), type(uint256).max);
        lpToken.approve(address(beefy), type(uint256).max);

        // @dev check for valid token0 and token1 from pool as poolFor generate the address
        (address t0, address t1) = aeroRouter.sortTokens(address(token0), address(token1));
        require(lpToken.token0() == t0 && lpToken.token1() == t1, "BAS: Invalid Aerodrome LP address");
    }

    /**
     * @notice calculate min/max amount after slippage
     * @param amount token amount
     * @param slippageBps slippage
     * @param isMin return min amount after slippage, otherwise return max amount
     */
    function _calculateSlippageAmount(uint256 amount, uint256 slippageBps, bool isMin)
        internal
        pure
        returns (uint256)
    {
        if (isMin) {
            return amount.mulDivDown(MAX_BPS - slippageBps, MAX_BPS);
        }
        return amount.mulDivDown(MAX_BPS, MAX_BPS - slippageBps);
    }

    /**
     * @notice return swapped token amount
     * @param from token to swap
     * @param to token swapped into
     * @param amount amount of from token
     */
    function _getSwapPrice(ERC20 from, ERC20 to, uint256 amount) internal view returns (uint256 tokenToAmount) {
        IAeroRouter.Route[] memory route = new IAeroRouter.Route[](1);

        route[0] = IAeroRouter.Route({from: address(from), to: address(to), stable: false, factory: factory});

        uint256[] memory amounts = aeroRouter.getAmountsOut(amount, route);
        return amounts[1];
    }

    /**
     * @notice return total LP token in the strategy
     */
    function _getTotalLpTokenAmount() internal view returns (uint256) {
        // beefy return price per share with 10^18 decimal
        return
            beefy.balanceOf(address(this)).mulWadDown(beefy.getPricePerFullShare()) + lpToken.balanceOf(address(this));
    }

    /**
     * @notice return asset equivalent token0 and token1 ratio in removing liquidity
     */
    function _getAssetsAmountFromLP() internal view returns (uint256) {
        uint256 lpTokenAmount = _getTotalLpTokenAmount();
        (uint256 token0Out, uint256 token1Out) =
            aeroRouter.quoteRemoveLiquidity(address(token0), address(token1), false, factory, lpTokenAmount);

        return token0Out + _getSwapPrice(token1, token0, token1Out);
    }

    /**
     * @notice swap token from to token to
     * @param from token to swap
     * @param to token swapped into
     * @param amount amount of from token
     * @param slippage max acceptable slippage in swap
     */
    function _swapToken(ERC20 from, ERC20 to, uint256 amount, uint256 slippage) internal {
        uint256 tokenToAmount = _getSwapPrice(from, to, amount);
        uint256 minTokenToReceive = _calculateSlippageAmount(tokenToAmount, slippage, true);

        IAeroRouter.Route[] memory route = new IAeroRouter.Route[](1);

        route[0] = IAeroRouter.Route({from: address(from), to: address(to), stable: false, factory: factory});

        aeroRouter.swapExactTokensForTokens(amount, minTokenToReceive, route, address(this), block.timestamp);
    }

    function _provideLiquidityToAero(uint256 token0Amount, uint256 token1Amount, uint256 slippage) internal {
        (uint256 token0Desired, uint256 token1desired,) =
            aeroRouter.quoteAddLiquidity(address(token0), address(token1), false, factory, token0Amount, token1Amount);

        uint256 minToken0Amount = _calculateSlippageAmount(token0Desired, slippage, true);
        uint256 minToken1Amount = _calculateSlippageAmount(token1desired, slippage, true);
        aeroRouter.addLiquidity(
            address(token0),
            address(token1),
            false,
            token0Desired,
            token1desired,
            minToken0Amount,
            minToken1Amount,
            address(this),
            block.timestamp
        );
    }

    function _removeLiquidityFromAero(uint256 lpTokenAmount, uint256 slippage) internal {
        (uint256 token0Out, uint256 token1Out) =
            aeroRouter.quoteRemoveLiquidity(address(token0), address(token1), false, factory, lpTokenAmount);

        uint256 minToken0Out = _calculateSlippageAmount(token0Out, slippage, true);
        uint256 minToken1Out = _calculateSlippageAmount(token1Out, slippage, true);

        aeroRouter.removeLiquidity(
            address(token0),
            address(token1),
            false,
            lpTokenAmount,
            minToken0Out,
            minToken1Out,
            address(this),
            block.timestamp
        );
    }

    function _investIntoBeefy(uint256 assets, uint256 slippage) internal {
        // we are utilizing the existing USDR idle from previous investment
        uint256 existingToken1EqToken0 = _getSwapPrice(token1, token0, token1.balanceOf(address(this)));
        uint256 totalAssetsToInvest = assets + existingToken1EqToken0;

        uint256 token0ToSwap = totalAssetsToInvest / 2;

        // swap token0/asset/USDC to token1/USDR
        if (token0ToSwap > existingToken1EqToken0) {
            token0ToSwap = token0ToSwap - existingToken1EqToken0;
            _swapToken(token0, token1, token0ToSwap, slippage);
        } else {
            token0ToSwap = 0;
        }
        // provide liquidity

        uint256 token0Amount = assets - token0ToSwap;
        uint256 token1Amount = token1.balanceOf(address(this));

        _provideLiquidityToAero(token0Amount, token1Amount, slippage);

        // deposit to beefy
        beefy.depositAll();
    }

    /**
     * @notice withdraw assets from beefy and liquidate lpToken to get asset
     * @param assets amount of asset to withdraw
     * @dev will transfer the assets to the vault
     */
    function _divest(uint256 assets) internal override returns (uint256) {
        _divestFromBeefy(assets, defaultSlippageBps);
        uint256 amountToSend = Math.min(assets, asset.balanceOf(address(this)));
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function _divestFromBeefy(uint256 assets, uint256 slippage) internal {
        if (assets <= asset.balanceOf(address(this))) {
            return;
        }

        _divestLP(assets - asset.balanceOf(address(this)), slippage);

        _swapToken(token1, token0, token1.balanceOf(address(this)), slippage);
    }

    /**
     * @notice divest LP token worth of assets amount
     * @param assets amount of assets required
     * @param slippage acceptable slippage
     */
    function _divestLP(uint256 assets, uint256 slippage) internal {
        // consider existing token1
        uint256 exToken1EqToken0 = _getSwapPrice(token1, token0, token1.balanceOf(address(this)));

        if (exToken1EqToken0 >= assets) {
            return;
        }

        uint256 requiredAssets = assets - exToken1EqToken0;

        uint256 totalAssetsInLP = _getAssetsAmountFromLP();

        uint256 lpTokenAmount = _getTotalLpTokenAmount().mulDivDown(requiredAssets, totalAssetsInLP);
        // withdraw from beefy
        if (lpTokenAmount > lpToken.balanceOf(address(this))) {
            _withdrawLPTokenFromBeefy(lpTokenAmount - lpToken.balanceOf(address(this)));
        }

        _removeLiquidityFromAero(lpToken.balanceOf(address(this)), slippage);
    }

    /**
     * @notice withdraw token from beefy
     * @param lpTokenAmount amount of token to withdraw
     */
    function _withdrawLPTokenFromBeefy(uint256 lpTokenAmount) internal {
        // shares to withdraw
        uint256 beefyShareToWithdraw = lpTokenAmount.divWadUp(beefy.getPricePerFullShare());

        // check for min shares
        beefyShareToWithdraw = Math.min(beefy.balanceOf(address(this)), beefyShareToWithdraw);

        beefy.withdraw(beefyShareToWithdraw);
    }

    function totalLockedValue() external view override returns (uint256) {
        return _getAssetsAmountFromLP() + token0.balanceOf(address(this))
            + _getSwapPrice(token1, token0, token1.balanceOf(address(this)));
    }

    function setDefaultSlippageBps(uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        require(defaultSlippageBps <= MAX_BPS, "BPS: invalid slippage bps");

        defaultSlippageBps = slippageBps;
    }

    function investAssets(uint256 amount, uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        require(amount <= asset.balanceOf(address(this)), "BPS: insufficient assets");
        _investIntoBeefy(amount, slippageBps);
    }

    function divestAssets(uint256 amount, uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        _divestFromBeefy(amount, slippageBps);
    }
}
