// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {PositionValue} from "@uniswap/v3-periphery/contracts/libraries/PositionValue.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    ILendingPoolAddressesProviderRegistry,
    ILendingPoolAddressesProvider,
    ILendingPool,
    IProtocolDataProvider
} from "../interfaces/aave.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

contract DeltaNeutralLpV3 is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(
        BaseVault _vault,
        uint256 _slippageTolerance,
        uint256 _longPct,
        ILendingPoolAddressesProviderRegistry _registry,
        ERC20 _borrowAsset,
        AggregatorV3Interface _borrowAssetFeed,
        ISwapRouter _router,
        INonfungiblePositionManager _lpManager,
        IUniswapV3Pool _pool
    ) BaseStrategy(_vault) {
        canStartNewPos = true;
        slippageTolerance = _slippageTolerance;
        longPercentage = _longPct;

        borrowAsset = _borrowAsset;
        borrowAssetFeed = _borrowAssetFeed;

        router = _router;
        lpManager = _lpManager;
        pool = _pool;
        poolFee = _pool.fee();
        assetIsToken0 = pool.token0() == address(asset);

        address[] memory providers = _registry.getAddressesProvidersList();
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(providers[providers.length - 1]);
        lendingPool = ILendingPool(provider.getLendingPool());
        debtToken = ERC20(lendingPool.getReserveData(address(borrowAsset)).variableDebtTokenAddress);
        aToken = ERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);

        // Depositing/withdrawing/repaying debt from lendingPool
        asset.safeApprove(address(lendingPool), type(uint256).max);
        aToken.safeApprove(address(lendingPool), type(uint256).max);
        borrowAsset.safeApprove(address(lendingPool), type(uint256).max);

        // To trade usdc/matic
        asset.safeApprove(address(_router), type(uint256).max);
        borrowAsset.safeApprove(address(_router), type(uint256).max);

        // To add liquidity
        asset.safeApprove(address(_lpManager), type(uint256).max);
        borrowAsset.safeApprove(address(_lpManager), type(uint256).max);
    }

    /// @notice Convert `borrowAsset` (e.g. MATIC) to `asset` (e.g. USDC)
    function _borrowToAsset(uint256 amountB) internal view returns (uint256 assets) {
        if (amountB == 0) {
            assets = 0;
            return assets;
        }

        uint256 price = _getPrice();

        // The first divisition gets rid of the decimals of wmatic. The second converts dollars to usdc
        // TODO: make this work for any set of decimals
        assets = (amountB * price) / (1e18 * 1e2);
    }

    function _getPrice() internal view returns (uint256 priceOfBorrowAsset) {
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = borrowAssetFeed.latestRoundData();
        require(price > 0, "Chainlink price <= 0");
        require(answeredInRound >= roundId, "Chainlink stale data");
        require(timestamp != 0, "Chainlink round not complete");

        priceOfBorrowAsset = uint256(price);
    }

    function valueOfLpPosition() public view returns (uint256 assetsLp) {
        if (lpId == 0) return assetsLp;
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        // Assume asset is token0
        (uint256 assetsInLp, uint256 borrowAssetsInLp) = PositionValue.total(lpManager, lpId, sqrtPriceX96);
        // Flip the amounts is asset is not token0
        if (!assetIsToken0) (borrowAssetsInLp, assetsInLp) = (assetsInLp, borrowAssetsInLp);
        assetsLp = assetsInLp + _borrowToAsset(borrowAssetsInLp);
    }

    function totalLockedValue() public view override returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfMatic + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens
        uint256 assetsMatic = _borrowToAsset(borrowAsset.balanceOf(address(this)));

        // Get value of uniswap lp position
        uint256 assetsLp = valueOfLpPosition();

        uint256 assetsDebt = _borrowToAsset(debtToken.balanceOf(address(this)));
        return balanceOfAsset() + assetsMatic + aToken.balanceOf(address(this)) + assetsLp - assetsDebt;
    }

    uint32 public currentPosition;
    bool public canStartNewPos;
    mapping(uint256 => uint256) public getPositionTime;

    event PositionStart(uint32 indexed position, uint256 timestamp);

    uint256 public slippageTolerance;
    /// @notice Fixed point number describing the percentage of the position with which to go long. 1e18 = 1 = 100%
    uint256 public longPercentage;

    /// @notice The router used for swaps
    ISwapRouter public immutable router;
    INonfungiblePositionManager public immutable lpManager;
    /// @notice The pool's fee. We need this to identify the pool.
    uint24 public immutable poolFee;
    IUniswapV3Pool public immutable pool;
    /// @notice True if `asset` is pool.token0();
    bool public immutable assetIsToken0;
    uint256 public lpId;
    uint128 public lpLiquidity;

    /// @notice The asset we want to borrow, e.g. WMATIC
    ERC20 public immutable borrowAsset;
    ILendingPool immutable lendingPool;
    /// @notice The asset we get when we borrow our `borrowAsset` from aave
    ERC20 public immutable debtToken;
    /// @notice The asset we get deposit `asset` into aave
    ERC20 public immutable aToken;

    /// @notice Gives ratio of vault asset to borrow asset, e.g. WMATIC/USD (assuming usdc = usd)
    AggregatorV3Interface immutable borrowAssetFeed;

    function startPosition() external onlyOwner {
        // Set position metadata
        require(canStartNewPos, "DNLP: position is active");
        uint32 newPositionId = currentPosition + 1;
        currentPosition = newPositionId;
        getPositionTime[newPositionId] = block.timestamp;
        canStartNewPos = false;
        emit PositionStart(newPositionId, block.timestamp);

        // Some amount of the assets will be used to buy matic at the end of this function
        uint256 assets = asset.balanceOf(address(this));
        uint256 assetsToMatic = assets.mulWadDown(longPercentage);

        // Borrow Matic at 75% (88% liquidation threshold and 85.5% max LTV)
        // If x is amount we want to deposit into aave
        // .75x = Total - x => 1.75x = Total => x = Total / 1.75 => Total * 4/7
        // Deposit asset in aave
        uint256 assetsToDeposit = (assets - assetsToMatic).mulDivDown(4, 7);
        lendingPool.deposit({asset: address(asset), amount: assetsToDeposit, onBehalfOf: address(this), referralCode: 0});

        // Convert assetsToDeposit into `borrowAsset` (e.g. WMATIC) units
        // assetsToDeposit has price units `asset`, price has units `asset / borrowAsset` ratio. so we divide by price
        // Scaling `asset` to 8 decimals since chainlink provides 8: https://docs.chain.link/docs/data-feeds/price-feeds/
        // TODO: handle both cases (assetDecimals > priceDecimals as well)
        uint256 borrowAssetsDeposited = (assetsToDeposit * 1e2 * 1e18) / _getPrice();

        // https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#borrow
        lendingPool.borrow({
            asset: address(borrowAsset),
            amount: borrowAssetsDeposited.mulDivDown(3, 4),
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: address(this)
        });

        // Provide liquidity on uniswap
        // TODO: make slippage parameterizable by caller, using min/max ticks for now
        uint256 aBal = assets - assetsToMatic - assetsToDeposit;
        uint256 bBal = borrowAsset.balanceOf(address(this));
        (, int24 tick,,,,,) = pool.slot0();
        _addLiquidity(aBal, bBal, 0, 0, tick - pool.tickSpacing() * 20, tick + pool.tickSpacing() * 20);

        // Buy WMATIC. After this trade, the strat now holds an lp NFT and a little bit of WMATIC
        address[] memory path = new address[](2);
        path[0] = address(asset);
        path[1] = address(borrowAsset);

        _swapExactSingle(asset, borrowAsset, assetsToMatic, 0);
    }

    /// @dev This strategy should be put at the end of the WQ so that we rarely divest from it. Divestment
    /// ideally occurs when the strategy does not have an open position
    function _divest(uint256 amount) internal override returns (uint256) {
        // Totally unwind the position
        if (!canStartNewPos) _endPosition();

        uint256 amountToSend = Math.min(amount, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        // Return the given amount
        return amountToSend;
    }

    event PositionEnd(uint32 indexed position, uint256 timestamp);

    function endPosition() external onlyOwner {
        _endPosition();
    }

    function _endPosition() internal {
        // Set position metadata
        require(!canStartNewPos, "DNLP: position is inactive");
        canStartNewPos = true;
        emit PositionEnd(currentPosition, block.timestamp);

        // Remove liquidity
        // TODO: handle slippage
        _removeLiquidity(0, 0);

        // Buy enough matic to pay back debt
        uint256 debt = debtToken.balanceOf(address(this));
        uint256 bBal = borrowAsset.balanceOf(address(this));
        uint256 maticToBuy = debt > bBal ? debt - bBal : 0;
        uint256 maticToSell = bBal > debt ? bBal - debt : 0;

        if (maticToBuy > 0) {
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);

            _swapExactOutputSingle(asset, borrowAsset, maticToBuy, type(uint256).max);
        }
        if (maticToSell > 0) {
            address[] memory path = new address[](2);
            path[0] = address(borrowAsset);
            path[1] = address(asset);

            _swapExactSingle(borrowAsset, asset, maticToSell, 0);
        }

        // Repay debt
        lendingPool.repay({asset: address(borrowAsset), amount: debt, rateMode: 2, onBehalfOf: address(this)});

        // Withdraw from aave
        lendingPool.withdraw({asset: address(asset), amount: aToken.balanceOf(address(this)), to: address(this)});
    }

    function _convertToAB(uint256 assets, uint256 borrowAssets) internal view returns (uint256, uint256) {
        if (assetIsToken0) return (assets, borrowAssets);
        else return (borrowAssets, assets);
    }

    function _addLiquidity(
        uint256 amountA,
        uint256 amountB,
        uint256 amountAMin,
        uint256 amountBMin,
        int24 minTick,
        int24 maxTick
    ) internal {
        (uint256 amount0, uint256 amount1) = _convertToAB(amountA, amountB);
        (uint256 amount0Min, uint256 amount1Min) = _convertToAB(amountAMin, amountBMin);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: assetIsToken0 ? address(asset) : address(borrowAsset),
            token1: assetIsToken0 ? address(borrowAsset) : address(asset),
            fee: poolFee,
            tickLower: minTick,
            tickUpper: maxTick,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp
        });
        (uint256 tokenId, uint128 liquidity,,) = lpManager.mint(params);
        lpId = tokenId;
        lpLiquidity = liquidity;
    }

    function _removeLiquidity(uint256 amountAMin, uint256 amountBMin) internal {
        (uint256 amount0Min, uint256 amount1Min) = _convertToAB(amountAMin, amountBMin);
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: lpId,
            liquidity: lpLiquidity,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });
        lpManager.decreaseLiquidity(params);
        // TODO: burn NFT
        lpLiquidity = 0;
    }

    function _swapExactSingle(ERC20 from, ERC20 to, uint256 amountIn, uint256 amountOutMinimum) internal {
        // Do a single swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(from),
            tokenOut: address(to),
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        router.exactInputSingle(params);
    }

    function _swapExactOutputSingle(ERC20 from, ERC20 to, uint256 amountOut, uint256 amountInMaximum) internal {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(from),
            tokenOut: address(to),
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        router.exactOutputSingle(params);
    }
}
