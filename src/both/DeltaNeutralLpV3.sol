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
        ERC20 _borrow,
        AggregatorV3Interface _borrowFeed,
        ISwapRouter _router,
        INonfungiblePositionManager _lpManager,
        IUniswapV3Pool _pool,
        IUniPositionValue _positionValue,
        address[] memory strategists,
        uint256 _assetToDepositRatioBps,
        uint256 _collateralToBorrowRatioBps
    ) AccessStrategy(_vault, strategists) {
        canStartNewPos = true;

        borrow = _borrow;
        borrowFeed = _borrowFeed;

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
        debtToken = ERC20(lendingPool.getReserveData(address(borrow)).variableDebtTokenAddress);
        aToken = ERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);

        // Depositing/withdrawing/repaying debt from lendingPool
        asset.safeApprove(address(lendingPool), type(uint256).max);
        aToken.safeApprove(address(lendingPool), type(uint256).max);
        borrow.safeApprove(address(lendingPool), type(uint256).max);

        // To trade asset/borrowAsset
        asset.safeApprove(address(_router), type(uint256).max);
        borrow.safeApprove(address(_router), type(uint256).max);

        // To add liquidity
        asset.safeApprove(address(_lpManager), type(uint256).max);
        borrow.safeApprove(address(_lpManager), type(uint256).max);

        decimalAdjustSign = asset.decimals() >= borrow.decimals() + borrowFeed.decimals() ? true : false;
        decimalAdjust = decimalAdjustSign
            ? asset.decimals() - borrowFeed.decimals() - borrow.decimals()
            : borrow.decimals() + borrowFeed.decimals() - asset.decimals();

        assetToDepositRatioBps = _assetToDepositRatioBps;
        collateralToBorrowRatioBps = _collateralToBorrowRatioBps;
    }

    /*//////////////////////////////////////////////////////////////
                               DIVESTMENT
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                          STRATEGY PARAMS
    //////////////////////////////////////////////////////////////*/

    /// @notice What fraction of asset to deposit into aave in bps
    uint256 public immutable assetToDepositRatioBps;
    /// @notice What fraction of collateral to borrow from aave in bps
    uint256 public immutable collateralToBorrowRatioBps;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////////
                          POSITION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a position is started.
     * @param position The position id.
     * @param assetCollateral The amount of `asset` deposited into aave.
     * @param borrows The amount of debt created.
     * @param borrowPrices Asset/Borrow prices. Index 0 contains the chainlink price of `borrow`.
     * Index 1 contains the spot (Uniswap) price.
     * @param tickLow The lower tick at which liquidity was provided.
     * @param tickHigh The higher ick at which liquidity was provided.
     * @param assetsToUni Amount of `asset` in uniswap lp position.
     * @param borrowsToUni Amount of `borrow` in uniswap lp position.
     * @param timestamp The block timestamp.
     */
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

    /// @notice The current position index. Starts at 0 and increases by 1 each time a new position is opened.
    uint32 public currentPosition;
    /// @notice True if we can start a new position. Only one position is allowed at a time.
    bool public canStartNewPos;

    /// @notice The asset we want to borrow, e.g. WMATIC
    ERC20 public immutable borrow;
    ///@dev Aave lending pool.
    ILendingPool immutable lendingPool;
    /// @dev Aave debt receipt token.
    ERC20 immutable debtToken;
    /// @dev Aave deposit receipt token.
    ERC20 public immutable aToken;

    /**
     * @notice Start a position.
     * @param tickLow The lower tick at which we will provide liquidity.
     * @param tickHigh The lower tick at which we will provide liquidity.
     * @param slippageToleranceBps Maximum bps of asset/borrow that will not be added as liquidity.
     */
    function startPosition(int24 tickLow, int24 tickHigh, uint256 slippageToleranceBps)
        external
        onlyRole(STRATEGIST_ROLE)
    {
        // Set position metadata
        require(canStartNewPos, "DNLP: position is active");
        currentPosition += 1;
        canStartNewPos = false;

        // Borrow at 75% LTV
        // If x is amount we want to deposit into aave
        // .75x = Total - x => 1.75x = Total => x = Total / 1.75 => Total * 4/7
        uint256 assets = asset.balanceOf(address(this));
        uint256 assetsToDeposit = assets.mulDivDown(assetToDepositRatioBps, MAX_BPS);
        lendingPool.deposit({asset: address(asset), amount: assetsToDeposit, onBehalfOf: address(this), referralCode: 0});

        uint256 borrowPrice = _getPrice();
        uint256 borrowsDeposited = _assetToBorrow(assetsToDeposit, borrowPrice);

        lendingPool.borrow({
            asset: address(borrow),
            amount: borrowsDeposited.mulDivDown(collateralToBorrowRatioBps, MAX_BPS),
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: address(this)
        });

        // Provide liquidity on uniswap
        (uint256 assetsToUni, uint256 borrowsToUni) = _addLiquidity(
            assets - assetsToDeposit, borrow.balanceOf(address(this)), tickLow, tickHigh, slippageToleranceBps
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

    /**
     * @notice Emitted when a position is closed.
     * @param  position The position id.
     * @param  assetsFromUni Amount of `asset` withdrawn from uniswap lp position.
     * @param borrowsFromUni Amount of `borrow` withdrawn from uniswap lp position.
     * @param assetFees Amount of fees (in `asset`) earned by uniswap lp position.
     * @param borrowFees Amount of fees (in `borrow`) earned by uniswap lp position.
     * @param borrowPrices Asset/Borrow prices. Index 0 contains the chainlink price of `borrow`.
     * Index 1 contains the spot (Uniswap) price.
     * @param assetSold True if we sold `asset` and bought `borrow`, false otherwise.
     * @param assetsOrBorrowsSold The amount of `asset` or `borrow` sold in order to repay the debt.
     * @param assetsOrBorrowsReceived The amount of `asset` or `borrow` received.
     * @param assetCollateral The aToken balance (before withdrawal from aave)
     * @param borrowDebtPaid The debt token balance (before repayment)
     * @param timestamp Block timestamp.
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

    /// @notice End position using at most `slippageBps` of slippage.
    function endPosition(uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        _endPosition(slippageBps);
    }

    /// @dev End posiion helper (also used during divestiment)
    function _endPosition(uint256 slippageBps) internal {
        // Set position metadata
        require(!canStartNewPos, "DNLP: position is inactive");
        canStartNewPos = true;

        // Remove liquidity
        (uint256 amount0FromUni, uint256 amount1FromUni, uint256 amount0Fees, uint256 amount1Fees) =
            _removeLiquidity(slippageBps);

        // Buy enough `borrow` to pay back debt
        uint256 debt;
        uint256 assetsOrBorrowsSold;
        uint256 assetsOrBorrowsReceived;
        bool assetSold;
        {
            debt = debtToken.balanceOf(address(this));
            uint256 bBal = borrow.balanceOf(address(this));
            uint256 borrowsToBuy = debt > bBal ? debt - bBal : 0;
            uint256 borrowsToSell = bBal > debt ? bBal - debt : 0;

            if (borrowsToBuy > 0) {
                (assetsOrBorrowsSold, assetsOrBorrowsReceived) =
                    _swapExactOutputSingle(asset, borrow, borrowsToBuy, slippageBps);
            }
            if (borrowsToSell > 0) {
                (assetsOrBorrowsSold, assetsOrBorrowsReceived) =
                    _swapExactSingle(borrow, asset, borrowsToSell, slippageBps);
            }
            assetSold = borrowsToBuy > 0;
        }

        // Repay debt
        lendingPool.repay({asset: address(borrow), amount: debt, rateMode: 2, onBehalfOf: address(this)});

        // Withdraw from aave
        uint256 assetCollateral = aToken.balanceOf(address(this));
        lendingPool.withdraw({asset: address(asset), amount: assetCollateral, to: address(this)});

        // Burn nft of position we are closing
        lpManager.burn(lpId);
        lpId = 0;

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

    /// @dev Emit end position event. Useful for avoiding stack-too-deep error.
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
        (uint256 assetsFromUni, uint256 borrowsFromUni) = _maybeFlip(amount0FromUni, amount1FromUni);
        (uint256 assetFees, uint256 borrowFees) = _maybeFlip(amount0Fees, amount1Fees);

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

    /*//////////////////////////////////////////////////////////////
                                UNISWAP
    //////////////////////////////////////////////////////////////*/

    /// @dev The uniswap router used for swaps.
    ISwapRouter public immutable router;
    /// @notice The uniswap nft manager (for adding/removing liquidity).
    INonfungiblePositionManager public immutable lpManager;
    /// @notice The pool's fee. We need this to identify the pool.
    uint24 public immutable poolFee;
    /// @notice The asset/borrow uniswap pool with fee `poolFee`.
    IUniswapV3Pool public immutable pool;
    address immutable token0;
    address immutable token1;

    /// @notice Id of our liquidity nft. Non-zero if a position is active.
    uint256 public lpId;
    /// @notice The amount of liquidity in our current position.
    uint128 public lpLiquidity;
    /// @notice A wrapper around the PositionValue lib (written in solidity 0.7)
    IUniPositionValue public immutable positionValue;

    /**
     * @dev Add liquidity to uniswap.
     * @param amountA The amount `asset` to deposit.
     * @param borrows The amount of `borrow` to deposit.
     * @param tickLow Lower liquidity tick.
     * @param tickHigh Higher liquidity tick.
     * @param  slippageToleranceBps Max slippage in bps.
     */
    function _addLiquidity(
        uint256 amountA,
        uint256 borrows,
        int24 tickLow,
        int24 tickHigh,
        uint256 slippageToleranceBps
    ) internal returns (uint256 assetsToUni, uint256 borrowsToUni) {
        (uint256 amount0, uint256 amount1) = _maybeFlip(amountA, borrows);
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
        (assetsToUni, borrowsToUni) = _maybeFlip(amount0Uni, amount1Uni);
        lpId = tokenId;
        lpLiquidity = liquidity;
    }

    /// @dev Remove liquidity from uniswap with at most `slippageBps` of slippage
    function _removeLiquidity(uint256 slippageBps)
        internal
        returns (uint256 amount0FromLiq, uint256 amount1FromLiq, uint256 amount0Fees, uint256 amount1Fees)
    {
        // Get the amounts that the position has collected in fees. The fees sent to this address.
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

    /// @dev Get value of lp nft tokens in terms of `token0` and `token1`.
    function _getTokensInLp() internal view returns (uint256 amount0, uint256 amount1) {
        if (lpLiquidity == 0) return (amount0, amount1);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        (amount0, amount1) = positionValue.total(lpManager, lpId, sqrtPriceX96);
    }

    /// @dev Collect amounts owed to us, whether do to fees or due to burning liquidity.
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

    /// @dev Swap `amountIn` of  `from` to `to` using at most `slippageBps` slippage.
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

    /// @dev Swap `from` to `amountOut` of `to` using at most `slippageBps` slippage.
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

    /*//////////////////////////////////////////////////////////////
                           FORMAT CONVERSIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Given two numbers in 01 (token0, token1) format, convert to our AB format (assets, borrows), and vice-versa.
    /// This will just flip the numbers if asset != token0.
    function _maybeFlip(uint256 amount0, uint256 amount1) internal view returns (uint256, uint256) {
        if (address(asset) == token0) return (amount0, amount1);
        else return (amount1, amount0);
    }

    /*//////////////////////////////////////////////////////////////
                             EXCHAGE RATES
    //////////////////////////////////////////////////////////////*/

    /// @dev Gives ratio of vault asset to borrow asset, e.g. WMATIC/USD (we assume that usd = usdc)
    AggregatorV3Interface immutable borrowFeed;

    /**
     * @notice abs(asset.decimals() - borrow.decimals() - borrowFeed.decimals()). Used when converting between
     * asset/borrow amounts
     */
    uint256 public immutable decimalAdjust;

    /// @notice true if asset.decimals() - borrow.decimals() - borrowFeed.decimals() is >= 0. false otherwise.
    bool public immutable decimalAdjustSign;

    /**
     * @dev Convert `borrow` (e.g. MATIC) to `asset` (e.g. USDC)
     * 10^borrow_decimals in `borrow` = clPrice / 10^borrowFeed_decimals * 10^asset_decimals in `assets`
     * thus borrows in `borrow` = borrows * clPrice * 10^(asset_decimals - borrow_decimals - borrowFeed_decimals)
     * Also note that, decimalAdjust = abs(asset_decimals - borrow_decimals - borrowFeed_decimals)
     */
    function _borrowToAsset(uint256 borrows, uint256 clPrice) internal view returns (uint256 assets) {
        if (decimalAdjustSign) {
            assets = borrows * clPrice * (10 ** decimalAdjust);
        } else {
            assets = borrows.mulDivDown(clPrice, 10 ** decimalAdjust);
        }
    }

    /// @dev Convert `asset` to `borrow`
    function _assetToBorrow(uint256 assets, uint256 clPrice) internal view returns (uint256 borrows) {
        if (decimalAdjustSign) {
            borrows = assets / (clPrice * (10 ** decimalAdjust));
        } else {
            borrows = assets.mulDivDown(10 ** decimalAdjust, clPrice);
        }
    }

    /// @dev Get chainlink ratio of asset/borrow.
    function _getPrice() internal view returns (uint256 priceOfborrow) {
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = borrowFeed.latestRoundData();
        require(price > 0, "Chainlink price <= 0");
        require(answeredInRound >= roundId, "Chainlink stale data");
        require(timestamp != 0, "Chainlink round not complete");

        priceOfborrow = uint256(price);
    }

    /// @dev Get equivalent `asset` amount of "one" (10 ** decimals()) borrow.
    function _getBorrowSpotPrice() internal view returns (uint256 price) {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        // We are converting "one" of `borrow` into some amount of `asset`.
        uint256 oneBorrow = 10 ** borrow.decimals();
        if (address(asset) == token0) {
            // eth_amount / (eth_usdc ratio)  = eth_amount * usdc/eth ratio = usdc amount
            price = (oneBorrow << 192) / (uint256(sqrtPriceX96) ** 2);
        } else {
            // eth_amount * usdc/eth ratio = usdc amount
            price = (oneBorrow * uint256(sqrtPriceX96) ** 2) >> 192;
        }
        return price;
    }

    /// @dev Convert `amountFrom` of `from` to the other token. This is a borrow -> asset or asset -> borrow conversion.
    function _convertAmounts(ERC20 from, uint256 amountFrom) internal view returns (uint256 amountTo) {
        uint256 borrowPrice = _getPrice();
        if (address(from) == address(asset)) {
            amountTo = _assetToBorrow(amountFrom, borrowPrice);
        } else {
            amountTo = _borrowToAsset(amountFrom, borrowPrice);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             TVL ESTIMATION
    //////////////////////////////////////////////////////////////*/

    function totalLockedValue() public view override returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfMatic + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens
        uint256 borrowPrice = _getPrice();
        uint256 assetsMatic = _borrowToAsset(borrow.balanceOf(address(this)), borrowPrice);

        // Get value of uniswap lp position
        uint256 assetsLp = valueOfLpPosition();

        uint256 assetsDebt = _borrowToAsset(debtToken.balanceOf(address(this)), borrowPrice);
        return balanceOfAsset() + assetsMatic + aToken.balanceOf(address(this)) + assetsLp - assetsDebt;
    }

    /// @notice The value of the lp position in `asset`.
    function valueOfLpPosition() public view returns (uint256 assetsLp) {
        (uint256 token0InLp, uint256 token1InLp) = _getTokensInLp();
        (uint256 assetsInLp, uint256 borrowsInLp) = _maybeFlip(token0InLp, token1InLp);
        assetsLp = assetsInLp + _borrowToAsset(borrowsInLp, _getPrice());
    }

    /// @notice The value of the fees accrued by the current lp position.
    function positionFees() public view returns (uint256 assets, uint256 borrows) {
        (uint256 token0Fees, uint256 token1Fees) = positionValue.fees(lpManager, lpId);
        return _maybeFlip(token0Fees, token1Fees);
    }
}
