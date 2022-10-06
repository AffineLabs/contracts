// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

contract DeltaNeutralLp is BaseStrategy, Ownable {
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
        IUniswapV3Pool _pool,
        uint24 _fee
    ) BaseStrategy(_vault) {
        canStartNewPos = true;
        slippageTolerance = _slippageTolerance;
        longPercentage = _longPct;

        borrowAsset = _borrowAsset;
        borrowAssetFeed = _borrowAssetFeed;

        router = _router;
        lpManager = _lpManager;
        pool = _pool;
        poolFee = _fee;

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
        asset.safeApprove(address(_lpManager), type(uint).max);
        borrowAsset.safeApprove(address(_lpManager), type(uint).max);
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

    function totalLockedValue() public override returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfMatic + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens

        uint256 assetsMatic = _borrowToAsset(borrowAsset.balanceOf(address(this)));

        // Calculate fees earned. We could calculate how much we are owed using code similar to this:
        // https://github.com/Uniswap/v3-periphery/blob/a0e0e5817528f0b810583c04feea17b696a16755/contracts/NonfungiblePositionManager.sol#L334-L347
        // But the feeGrowthInside{0,1}LastX128 numbers are old unless you mint/burn some liquidity

        // So we simply "poke" the position (increaseLiquidity using zero input tokens) and let uniswap update our fees for us
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: lpId,
            amount0Desired: 0,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        lpManager.increaseLiquidity(params);

        // TODO: Figure out if `asset` is `token0` of the pool in the constructor
        // These amounts owed include both the amount of tokens we have and the amount of fees we've earned
        (,,,,,,,,,, uint128 tokensOwed0, uint128 tokensOwed1) = lpManager.positions(lpId);
        uint256 assetInLp = address(asset) == pool.token0() ? tokensOwed0 : tokensOwed1;
        uint256 borrowAssetInLp =
            address(asset) == pool.token0() ? _borrowToAsset(tokensOwed1) : _borrowToAsset(tokensOwed1);
        uint256 assetsLp = assetInLp + borrowAssetInLp;

        uint256 assetsDebt = _borrowToAsset(debtToken.balanceOf(address(this)));
        return balanceOfAsset() + assetsMatic + aToken.balanceOf(address(this)) + assetsLp - assetsDebt;
    }

    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
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
        uint256 bBal = borrowAsset.balanceOf(address(this));
        uint256 aBal = assets - assetsToMatic - assetsToDeposit;
        _addLiquidity(aBal, bBal, aBal.mulDivDown(98, 100), bBal.mulDivDown(98, 100), -887_272, -(-887_272));

        // Buy Matic. After this trade, the strat now holds only lp tokens and a little bit of matic
        address[] memory path = new address[](2);
        path[0] = address(asset);
        path[1] = address(borrowAsset);

        _swapExactSingle(asset, borrowAsset, assetsToMatic, 0);
    }

    /// @dev This strategy should be put at the end of the WQ so that we rarely divest from it. Divestment
    /// ideally occurs when the strategy does not have an open position
    function divest(uint256 amount) external override onlyVault returns (uint256) {
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

    function _collectFees() internal {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lpId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        lpManager.collect(params);
    }

    function _addLiquidity(
        uint256 amountA,
        uint256 amountB,
        uint256 amountAMin,
        uint256 amountBMin,
        int24 minTick,
        int24 maxTick
    ) internal {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(asset),
            token1: address(borrowAsset),
            fee: poolFee,
            tickLower: minTick,
            tickUpper: maxTick,
            amount0Desired: amountA,
            amount1Desired: amountB,
            amount0Min: amountAMin,
            amount1Min: amountBMin,
            recipient: address(this),
            deadline: block.timestamp
        });
        (uint256 tokenId, uint128 liquidity,,) = lpManager.mint(params);
        lpId = tokenId;
        lpLiquidity = liquidity;
    }

    function _removeLiquidity(uint256 amountAMin, uint256 amountBMin) internal {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: lpId,
            liquidity: lpLiquidity,
            amount0Min: amountAMin,
            amount1Min: amountBMin,
            deadline: block.timestamp
        });
        lpManager.decreaseLiquidity(params);
        // TODO: burn NFT
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
