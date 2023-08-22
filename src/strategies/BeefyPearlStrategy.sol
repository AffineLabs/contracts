// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {IRouter, IPair} from "src/interfaces/IPearl.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";

import {AffineVault} from "src/vaults/Vault.sol";

contract BeefyPearlStrategy is AccessStrategy {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // beefy vault
    IBeefyVault public immutable beefy;
    // const max bps
    uint256 public constant MAX_BPS = 10_000;
    uint256 public defaultSlippageBps;

    ERC20 public immutable token0;
    ERC20 public immutable token1;

    IRouter public immutable pearlRouter;
    IPair public immutable lpToken;

    constructor(AffineVault _vault, IBeefyVault _beefy, IRouter _router, ERC20 _token1, address[] memory strategists)
        AccessStrategy(_vault, strategists)
    {
        beefy = _beefy;
        token0 = asset;
        token1 = _token1;

        pearlRouter = _router;
        lpToken = IPair(pearlRouter.pairFor(address(token0), address(token1), true));

        require(pearlRouter.isPair(address(lpToken)), "BPS: invalid pearl LP pair");
    }

    // TODO: parameterize (address from, address to)
    function _getInLPRatio() internal view returns (uint256, uint256) {
        (uint256 token0Desired, uint256 token1desired,) = pearlRouter.quoteAddLiquidity(
            address(token0), address(token1), true, 10 ** token0.decimals(), 10 ** token1.decimals()
        );

        (uint256 token0ToToken1SwapPrice,) =
            pearlRouter.getAmountOut(10 ** token0.decimals(), address(token0), address(token1));

        uint256 token1EqToken0 = token1desired.mulDivDown(10 ** token0.decimals(), token0ToToken1SwapPrice);

        return (token0Desired, token1EqToken0);
    }

    function _getTotalLpTokenAmount() internal view returns (uint256) {
        return beefy.balanceOf(address(this)).mulDivDown(beefy.getPricePerFullShare(), 10 ** beefy.decimals())
            + lpToken.balanceOf(address(this));
    }

    function _getOutLPRatio() internal view returns (uint256, uint256) {
        uint256 lpTokenAmount = _getTotalLpTokenAmount();
        (uint256 token0Out, uint256 token1Out) =
            pearlRouter.quoteRemoveLiquidity(address(token0), address(token1), true, lpTokenAmount);

        (uint256 token1ToToken0SwapPrice,) =
            pearlRouter.getAmountOut(10 ** token1.decimals(), address(token1), address(token0));

        uint256 token1EqToken0 = token1Out.mulDivDown(token1ToToken0SwapPrice, 10 ** token1.decimals());

        return (token0Out, token1EqToken0);
    }

    function _swapToken(ERC20 from, ERC20 to, uint256 amount, uint256 slippage) internal {
        require(from.balanceOf(address(this)) <= amount, "BPS: INSUFFICIENT BALANCE FOR SWAP T0 -> T1");

        (uint256 tokenToAmount,) = pearlRouter.getAmountOut(amount, address(from), address(to));
        uint256 minTokenToReceive = _calculateSlippageAmount(tokenToAmount, slippage, true);
        pearlRouter.swapExactTokensForTokensSimple(
            amount, minTokenToReceive, address(from), address(to), true, address(this), block.number + 2
        );
    }

    function _provideLiquidityToPearl(uint256 token0Amount, uint256 token1Amount, uint256 slippage) internal {
        uint256 minToken0Amount = _calculateSlippageAmount(token0Amount, slippage, true);
        uint256 minToken1Amount = _calculateSlippageAmount(token1Amount, slippage, true);
        pearlRouter.addLiquidity(
            address(token0),
            address(token1),
            true,
            token0Amount,
            token1Amount,
            minToken0Amount,
            minToken1Amount,
            address(this),
            block.number + 2
        );
    }

    function _removeLiquidityFromPearl(uint256 lpTokenAmount, uint256 slippage) internal {
        (uint256 token0Out, uint256 token1Out) =
            pearlRouter.quoteRemoveLiquidity(address(token0), address(token1), true, lpTokenAmount);

        uint256 minToken0Out = _calculateSlippageAmount(token0Out, slippage, true);
        uint256 minToken1Out = _calculateSlippageAmount(token1Out, slippage, true);

        pearlRouter.removeLiquidity(
            address(token0),
            address(token1),
            true,
            lpTokenAmount,
            minToken0Out,
            minToken1Out,
            address(this),
            block.number + 2
        );
    }

    function _investIntoBeefy(uint256 assets, uint256 slippage) internal {
        (uint256 token0Ratio, uint256 token1ratio) = _getInLPRatio();
        // check for slippage
        token1ratio = _calculateSlippageAmount(token1ratio, slippage, false);

        uint256 token0ToSwap = assets.mulDivDown(token1ratio, token0Ratio + token1ratio);

        // swap token0/asset/USDC to token1/USDR
        _swapToken(token0, token1, token0ToSwap, slippage);
        // provide liquidity

        uint256 token0Amount = assets - token0ToSwap;
        uint256 token1Amount = token1.balanceOf(address(this));

        _provideLiquidityToPearl(token0Amount, token1Amount, slippage);

        // deposit to beefy
        beefy.depositAll();
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
     * @notice withdraw assets from beefy and liquidate lpToken to get asset
     * @param assets amount of asset to withdraw
     * @dev will transfer the assets to the vault
     */
    function _divest(uint256 assets) internal override returns (uint256) {
        _divestFromBeefy(assets, defaultSlippageBps);
        return Math.min(asset.balanceOf(address(this)), assets);
    }

    function _divestFromBeefy(uint256 assets, uint256 slippage) internal {
        uint256 requiredAssets = assets - asset.balanceOf(address(this));

        (uint256 token0Ratio, uint256 token1Ratio) = _getOutLPRatio();

        // calc slippage calc 1
        uint256 minToken1Ratio = _calculateSlippageAmount(token1Ratio, slippage, true);

        uint256 totalLpToken = _getTotalLpTokenAmount();

        uint256 lpTokenAmount = totalLpToken.mulDivDown(requiredAssets, token0Ratio + minToken1Ratio);

        // withdraw from beefy
        if (lpTokenAmount < lpToken.balanceOf(address(this))) {
            _withdrawLPTokenFromBeefy(lpTokenAmount - lpToken.balanceOf(address(this)));
        }

        _removeLiquidityFromPearl(lpToken.balanceOf(address(this)), slippage);

        _swapToken(token1, token0, token1.balanceOf(address(this)), slippage);
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
        (uint256 token0Amount, uint256 token1EqToken0Amount) = _getOutLPRatio();

        return token0Amount + token1EqToken0Amount + token0.balanceOf(address(this)) + token1.balanceOf(address(this));
    }

    function setDefaultSlippageBps(uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        require(defaultSlippageBps <= MAX_BPS, "BS: invalid slippage bps");

        defaultSlippageBps = slippageBps;
    }

    function investAssets(uint256 amount, uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        require(amount <= asset.balanceOf(address(this)), "BS: insufficient assets");
        _investIntoBeefy(amount, slippageBps);
    }

    function divestAssets(uint256 amount, uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        _divestFromBeefy(amount, slippageBps);
    }
}
