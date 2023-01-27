// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    ILendingPoolAddressesProviderRegistry,
    ILendingPoolAddressesProvider,
    ILendingPool,
    IProtocolDataProvider
} from "../interfaces/aave.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IUniPositionValue} from "../interfaces/IUniPositionValue.sol";

import {BaseVault} from "../BaseVault.sol";
import {AccessStrategy} from "./AccessStrategy.sol";
import {SlippageUtils} from "../libs/SlippageUtils.sol";

contract DeltaNeutralLpV3 is AccessStrategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    constructor(
        BaseVault _vault,
        ILendingPoolAddressesProviderRegistry _registry,
        ERC20 _borrowAsset,
        AggregatorV3Interface _borrowAssetFeed,
        ISwapRouter _router,
        INonfungiblePositionManager _lpManager,
        IUniswapV3Pool _pool,
        IUniPositionValue _positionValue,
        address[] memory strategists
    ) AccessStrategy(_vault, strategists) {
        canStartNewPos = true;

        borrowAsset = _borrowAsset;
        borrowAssetFeed = _borrowAssetFeed;

        // Uni info
        router = _router;
        lpManager = _lpManager;
        pool = _pool;
        poolFee = _pool.fee();
        token0 = pool.token0();
        token1 = pool.token1();
        positionValue = _positionValue;

        address[] memory providers = _registry.getAddressesProvidersList();
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(providers[providers.length - 1]);
        lendingPool = ILendingPool(provider.getLendingPool());
        debtToken = ERC20(lendingPool.getReserveData(address(borrowAsset)).variableDebtTokenAddress);
        aToken = ERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);

        // Depositing/withdrawing/repaying debt from lendingPool
        asset.safeApprove(address(lendingPool), type(uint256).max);
        aToken.safeApprove(address(lendingPool), type(uint256).max);
        borrowAsset.safeApprove(address(lendingPool), type(uint256).max);

        // To trade asset/borrowAsset
        asset.safeApprove(address(_router), type(uint256).max);
        borrowAsset.safeApprove(address(_router), type(uint256).max);

        // To add liquidity
        asset.safeApprove(address(_lpManager), type(uint256).max);
        borrowAsset.safeApprove(address(_lpManager), type(uint256).max);

        // xyz/eth chainlink feeds has 18 decimals and xyz/usd chainlink feeds has 8 decimals.
        decimalDiff = (address(asset) == WETH ? 18 : 8) - asset.decimals();
    }

    /// @notice Convert `borrowAsset` (e.g. MATIC) to `asset` (e.g. USDC)
    function _borrowToAsset(uint256 amountB, uint256 clPrice) internal view returns (uint256 assets) {
        // The first divisition gets rid of the decimals of `borrowAsset`. The second converts dollars to `asset`
        if (decimalDiff < 0) {
            assets = (amountB * (10 ** decimalDiff)).mulWadDown(clPrice);
        } else {
            assets = amountB.mulWadDown(clPrice) / (10 ** decimalDiff);
        }
    }

    function _assetToBorrow(uint256 assets, uint256 clPrice) internal view returns (uint256 borrows) {
        if (decimalDiff < 0) {
            borrows = assets.divWadDown(clPrice) / (10 ** decimalDiff);
        } else {
            borrows = (assets * (10 ** decimalDiff)).divWadDown(clPrice);
        }
    }

    function _getPrice() internal view returns (uint256 priceOfBorrowAsset) {
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = borrowAssetFeed.latestRoundData();
        require(price > 0, "Chainlink price <= 0");
        require(answeredInRound >= roundId, "Chainlink stale data");
        require(timestamp != 0, "Chainlink round not complete");

        priceOfBorrowAsset = uint256(price);
    }

    function valueOfLpPosition() public view returns (uint256 assetsLp) {
        (uint256 token0InLp, uint256 token1InLp) = _getTokensInLp();
        (uint256 assetsInLp, uint256 borrowAssetsInLp) = _convertToAB(token0InLp, token1InLp);
        assetsLp = assetsInLp + _borrowToAsset(borrowAssetsInLp, _getPrice());
    }

    function _getTokensInLp() internal view returns (uint256 amount0, uint256 amount1) {
        if (lpLiquidity == 0) return (amount0, amount1);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        (amount0, amount1) = positionValue.total(lpManager, lpId, sqrtPriceX96);
    }

    function positionFees() public view returns (uint256 assets, uint256 borrows) {
        (uint256 token0Fees, uint256 token1Fees) = positionValue.fees(lpManager, lpId);
        return _convertToAB(token0Fees, token1Fees);
    }

    function totalLockedValue() public view override returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfMatic + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens
        uint256 borrowPrice = _getPrice();
        uint256 assetsMatic = _borrowToAsset(borrowAsset.balanceOf(address(this)), borrowPrice);

        // Get value of uniswap lp position
        uint256 assetsLp = valueOfLpPosition();

        uint256 assetsDebt = _borrowToAsset(debtToken.balanceOf(address(this)), borrowPrice);
        return balanceOfAsset() + assetsMatic + aToken.balanceOf(address(this)) + assetsLp - assetsDebt;
    }

    uint32 public currentPosition;
    bool public canStartNewPos;

    event PositionStart(
        uint32 indexed position,
        uint256 assetCollateral,
        uint256 borrows,
        uint256[2] borrowPrices,
        int24 tickLow,
        int24 tickHigh,
        uint256 assetsToUni,
        uint256 borrowsToUni,
        uint256 timestamp
    );

    /// @notice The router used for swaps
    ISwapRouter public immutable router;
    INonfungiblePositionManager public immutable lpManager;
    /// @notice The pool's fee. We need this to identify the pool.
    uint24 public immutable poolFee;
    IUniswapV3Pool public immutable pool;
    /// @notice True if `asset` is pool.token0();
    address immutable token0;
    address immutable token1;
    uint256 public lpId;
    uint128 public lpLiquidity;
    /// @notice A wrapper around the positionValue lib (written in solidity 0.7)
    IUniPositionValue public immutable positionValue;

    /// @notice The asset we want to borrow, e.g. WMATIC
    ERC20 public immutable borrowAsset;
    ILendingPool immutable lendingPool;
    /// @notice The asset we get when we borrow our `borrowAsset` from aave
    ERC20 public immutable debtToken;
    /// @notice The asset we get deposit `asset` into aave
    ERC20 public immutable aToken;

    /// @notice Gives ratio of vault asset to borrow asset, e.g. WMATIC/USD (assuming usdc = usd)
    AggregatorV3Interface immutable borrowAssetFeed;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public immutable decimalDiff;

    function startPosition(int24 tickLow, int24 tickHigh, uint256 slippageToleranceBps)
        external
        onlyRole(STRATEGIST_ROLE)
    {
        // Set position metadata
        require(canStartNewPos, "DNLP: position is active");
        currentPosition += 1;
        canStartNewPos = false;

        // Borrow Matic at 75% (88% liquidation threshold and 85.5% max LTV)
        // If x is amount we want to deposit into aave
        // .75x = Total - x => 1.75x = Total => x = Total / 1.75 => Total * 4/7
        // Deposit asset in aave
        uint256 assets = asset.balanceOf(address(this));
        uint256 assetsToDeposit = assets.mulDivDown(4, 7);
        lendingPool.deposit({asset: address(asset), amount: assetsToDeposit, onBehalfOf: address(this), referralCode: 0});

        uint256 borrowPrice = _getPrice();
        uint256 borrowAssetsDeposited = _assetToBorrow(assetsToDeposit, borrowPrice);

        // https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#borrow
        lendingPool.borrow({
            asset: address(borrowAsset),
            amount: borrowAssetsDeposited.mulDivDown(3, 4),
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: address(this)
        });

        // Provide liquidity on uniswap
        (uint256 assetsToUni, uint256 borrowsToUni) = _addLiquidity(
            assets - assetsToDeposit, borrowAsset.balanceOf(address(this)), tickLow, tickHigh, slippageToleranceBps
        );

        emit PositionStart({
            position: currentPosition,
            assetCollateral: aToken.balanceOf(address(this)),
            borrows: debtToken.balanceOf(address(this)),
            borrowPrices: [borrowPrice, _getBorrowSpotPrice()],
            tickLow: tickLow,
            tickHigh: tickHigh,
            assetsToUni: assetsToUni,
            borrowsToUni: borrowsToUni,
            timestamp: block.timestamp
        });
    }

    /// @dev This strategy should be put at the end of the WQ so that we rarely divest from it. Divestment
    /// ideally occurs when the strategy does not have an open position
    function _divest(uint256 amount) internal override returns (uint256) {
        // Totally unwind the position
        if (!canStartNewPos) _endPosition(500);

        uint256 amountToSend = Math.min(amount, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        // Return the given amount
        return amountToSend;
    }

    /**
     * @param assetSold True if we sold asset and bough borrow, false otherwise
     * @param assetsOrBorrowsSold The amount of asset or borrow sold in order to repay the debt
     */
    event PositionEnd(
        uint32 indexed position,
        uint256 assetsFromUni,
        uint256 borrowsFromUni,
        uint256 assetFees,
        uint256 borrowFees,
        uint256[2] borrowPrices,
        bool assetSold,
        uint256 assetsOrBorrowsSold,
        uint256 assetsOrBorrowsReceived,
        uint256 assetCollateral,
        uint256 borrowDebtPaid,
        uint256 timestamp
    );

    function endPosition(uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        _endPosition(slippageBps);
    }

    function _endPosition(uint256 slippageBps) internal {
        // Set position metadata

        require(!canStartNewPos, "DNLP: position is inactive");
        canStartNewPos = true;

        // Remove liquidity
        (uint256 amount0FromUni, uint256 amount1FromUni, uint256 amount0Fees, uint256 amount1Fees) =
            _removeLiquidity(slippageBps);

        // Buy enough `borrowAsset` to pay back debt
        uint256 debt;
        uint256 assetsOrBorrowsSold;
        uint256 assetsOrBorrowsReceived;
        bool assetSold;
        {
            debt = debtToken.balanceOf(address(this));
            uint256 bBal = borrowAsset.balanceOf(address(this));
            uint256 borrowAssetToBuy = debt > bBal ? debt - bBal : 0;
            uint256 borrowAssetToSell = bBal > debt ? bBal - debt : 0;

            if (borrowAssetToBuy > 0) {
                (assetsOrBorrowsSold, assetsOrBorrowsReceived) =
                    _swapExactOutputSingle(asset, borrowAsset, borrowAssetToBuy, slippageBps);
            }
            if (borrowAssetToSell > 0) {
                (assetsOrBorrowsSold, assetsOrBorrowsReceived) =
                    _swapExactSingle(borrowAsset, asset, borrowAssetToSell, slippageBps);
            }
            assetSold = borrowAssetToBuy > 0;
        }

        // Repay debt
        lendingPool.repay({asset: address(borrowAsset), amount: debt, rateMode: 2, onBehalfOf: address(this)});

        // Withdraw from aave
        uint256 assetCollateral = aToken.balanceOf(address(this));
        lendingPool.withdraw({asset: address(asset), amount: assetCollateral, to: address(this)});

        // Burn nft of position we are closing
        lpManager.burn(lpId);
        lpId = 0;

        // This function is just being used to avoid the stack too deep error
        _emitEnd(
            amount0FromUni,
            amount1FromUni,
            amount0Fees,
            amount1Fees,
            assetSold,
            assetsOrBorrowsSold,
            assetsOrBorrowsReceived,
            assetCollateral,
            debt
        );
    }

    /// @dev Another function to avoid stack too deep error. Via-ir compilation takes too long.
    function _getBorrowSpotPrice() internal view returns (uint256 price) {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        // We are converting "one" of `borrowAsset` into some amount of `asset`.
        uint256 oneBorrow = 10 ** borrowAsset.decimals();
        if (address(asset) == token0) {
            // borrow amount / (borrow : asset ratio) = asset amount
            price = (oneBorrow << 192) / (uint256(sqrtPriceX96) ** 2);
        } else {
            // borrow amount * (asset : borrow ratio) = asset amount
            price = (oneBorrow * uint256(sqrtPriceX96) ** 2) >> 192;
        }
        return price;
    }

    function _emitEnd(
        uint256 amount0FromUni,
        uint256 amount1FromUni,
        uint256 amount0Fees,
        uint256 amount1Fees,
        bool assetSold,
        uint256 assetsOrBorrowsSold,
        uint256 assetsOrBorrowsReceived,
        uint256 assetCollateral,
        uint256 debt
    ) internal {
        (uint256 assetsFromUni, uint256 borrowsFromUni) = _convertToAB(amount0FromUni, amount1FromUni);
        (uint256 assetFees, uint256 borrowFees) = _convertToAB(amount0Fees, amount1Fees);

        {
            emit PositionEnd({
                position: currentPosition,
                assetsFromUni: assetsFromUni,
                borrowsFromUni: borrowsFromUni,
                assetFees: assetFees,
                borrowFees: borrowFees,
                borrowPrices: [_getPrice(), _getBorrowSpotPrice()],
                assetSold: assetSold,
                assetsOrBorrowsSold: assetsOrBorrowsSold,
                assetsOrBorrowsReceived: assetsOrBorrowsReceived,
                assetCollateral: assetCollateral,
                borrowDebtPaid: debt,
                timestamp: block.timestamp
            });
        }
    }

    /// @dev Given two numbers in AB (assets, borrows) format, convert to Uniswap's token0, token1 format
    function _convertTo01(uint256 assets, uint256 borrowAssets) internal view returns (uint256, uint256) {
        if (address(asset) == token0) return (assets, borrowAssets);
        else return (borrowAssets, assets);
    }

    /// @dev Given two numbers in 01 (token0, token1) format, convert to our AB format (assets, borrows). This will just flip
    /// the numbers if asset != token0.
    function _convertToAB(uint256 amount0, uint256 amount1) internal view returns (uint256, uint256) {
        return _convertTo01(amount0, amount1);
    }

    function _addLiquidity(
        uint256 amountA,
        uint256 amountB,
        int24 tickLow,
        int24 tickHigh,
        uint256 slippageToleranceBps
    ) internal returns (uint256 assetsToUni, uint256 borrowsToUni) {
        (uint256 amount0, uint256 amount1) = _convertTo01(amountA, amountB);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: tickLow,
            tickUpper: tickHigh,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0.slippageDown(slippageToleranceBps),
            amount1Min: amount1.slippageDown(slippageToleranceBps),
            recipient: address(this),
            deadline: block.timestamp
        });
        (uint256 tokenId, uint128 liquidity, uint256 amount0Uni, uint256 amount1Uni) = lpManager.mint(params);
        (assetsToUni, borrowsToUni) = _convertToAB(amount0Uni, amount1Uni);
        lpId = tokenId;
        lpLiquidity = liquidity;
    }

    function _removeLiquidity(uint256 slippageBps)
        internal
        returns (uint256 amount0FromLiq, uint256 amount1FromLiq, uint256 amount0Fees, uint256 amount1Fees)
    {
        // Get the amounts that the position has collected in fees. The fees are also sent to this address
        (amount0Fees, amount1Fees) = _collectFees();

        // Get amount of tokens in our lp position
        (uint256 amount0InLp, uint256 amount1InLp) = _getTokensInLp();

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: lpId,
            liquidity: lpLiquidity,
            amount0Min: amount0InLp.slippageDown(slippageBps),
            amount1Min: amount1InLp.slippageDown(slippageBps),
            deadline: block.timestamp
        });
        lpManager.decreaseLiquidity(params);
        lpLiquidity = 0;

        // After decreasing the liquidity, the amounts received are the tokens owed to us from the burnt liquidity
        (amount0FromLiq, amount1FromLiq) = _collectFees();
    }

    function _collectFees() internal returns (uint256 amount0, uint256 amount1) {
        // This will actually transfer the tokens owed after decreasing the liquidity
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lpId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = lpManager.collect(params);
    }

    function _convertAmounts(ERC20 from, uint256 amountFrom) internal view returns (uint256 amountTo) {
        uint256 borrowPrice = _getPrice();
        if (address(from) == address(asset)) {
            amountTo = _assetToBorrow(amountFrom, borrowPrice);
        } else {
            amountTo = _borrowToAsset(amountFrom, borrowPrice);
        }
    }

    function _swapExactSingle(ERC20 from, ERC20 to, uint256 amountIn, uint256 slippageBps)
        internal
        returns (uint256 sold, uint256 received)
    {
        uint256 amountOut = _convertAmounts(from, amountIn);
        // Do a single swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(from),
            tokenOut: address(to),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOut.slippageDown(slippageBps),
            sqrtPriceLimitX96: 0
        });

        received = router.exactInputSingle(params);
        sold = amountIn;
    }

    function _swapExactOutputSingle(ERC20 from, ERC20 to, uint256 amountOut, uint256 slippageBps)
        internal
        returns (uint256 sold, uint256 received)
    {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(from),
            tokenOut: address(to),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: amountOut,
            // When amountOut is very small the conversion may truncate to zero. Set a floor of one whole token
            amountInMaximum: Math.max(_convertAmounts(to, amountOut).slippageUp(slippageBps), 10 ** ERC20(from).decimals()),
            sqrtPriceLimitX96: 0
        });

        sold = router.exactOutputSingle(params);
        received = amountOut;
    }
}
