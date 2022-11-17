// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SlippageUtils} from "../libs/SlippageUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {
    ILendingPoolAddressesProviderRegistry,
    ILendingPoolAddressesProvider,
    ILendingPool,
    IProtocolDataProvider
} from "../interfaces/aave.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {IMiniChef} from "../interfaces/sushiswap/IMiniChef.sol";

contract L2DeltaNeutralLp is BaseStrategy, AccessControl {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    constructor(
        BaseVault _vault,
        uint256 _longPct,
        ILendingPoolAddressesProviderRegistry _registry,
        ERC20 _borrowAsset,
        AggregatorV3Interface _borrowAssetFeed,
        IUniswapV2Router02 _router,
        IMiniChef _miniChef
    ) BaseStrategy(_vault) {
        _grantRole(DEFAULT_ADMIN_ROLE, vault.governance());
        _grantRole(STRATEGIST_ROLE, vault.governance());

        canStartNewPos = true;
        longPercentage = _longPct;

        borrowAsset = _borrowAsset;
        borrowAssetFeed = _borrowAssetFeed;

        router = _router;
        abPair = ERC20(IUniswapV2Factory(_router.factory()).getPair(address(asset), address(borrowAsset)));
        address[] memory providers = _registry.getAddressesProvidersList();
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(providers[providers.length - 1]);
        lendingPool = ILendingPool(provider.getLendingPool());
        debtToken = ERC20(lendingPool.getReserveData(address(borrowAsset)).variableDebtTokenAddress);
        aToken = ERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);

        miniChef = _miniChef;
        uint256 miniChefPoolLength = _miniChef.poolLength();
        miniChefPid = miniChefPoolLength + 1;
        for (uint256 pid = 0; pid < miniChefPoolLength; pid++) {
            if (miniChef.lpToken(pid) == address(abPair)) {
                miniChefPid = pid;
                break;
            }
        }
        require(miniChefPid != miniChefPoolLength + 1, "DNLP: pool not found");
        sushiToken = ERC20(_miniChef.sushi());

        // Depositing/withdrawing/repaying debt from lendingPool
        asset.safeApprove(address(lendingPool), type(uint256).max);
        aToken.safeApprove(address(lendingPool), type(uint256).max);
        borrowAsset.safeApprove(address(lendingPool), type(uint256).max);

        // To trade usdc/matic
        asset.safeApprove(address(_router), type(uint256).max);
        borrowAsset.safeApprove(address(_router), type(uint256).max);
        // To remove liquidity
        abPair.safeApprove(address(_router), type(uint256).max);
        // For staging SLP token
        abPair.safeApprove(address(_miniChef), type(uint256).max);
        // For trading shushi/usdc
        sushiToken.safeApprove(address(_router), type(uint256).max);
    }

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST");
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Get price of WMATIC in USDC (borrowPrice) from chainlink. Has 8 decimals.
    function _chainlinkPriceOfBorrow() internal view returns (uint256 borrowPrice) {
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = borrowAssetFeed.latestRoundData();
        require(price > 0, "DNLP: price <= 0");
        require(answeredInRound >= roundId, "DNLP: stale data");
        require(timestamp != 0, "DNLP: round not done");
        borrowPrice = uint256(price); // Convert 8 decimals to 6 decimals, 1 WMATIC (1e18) = price USDC
    }

    /// @notice Get price of WMATIC in USDC (borrowPrice) from Sushiswap. Has 8 decimals.
    function _sushiPriceOfBorrow() internal view returns (uint256 borrowPrice) {
        address[] memory path = new address[](2);
        path[0] = address(borrowAsset);
        path[1] = address(asset);

        uint256[] memory amounts = router.getAmountsOut({amountIn: 1e18, path: path});
        return amounts[1] * 1e2;
    }

    /// @notice Convert `borrowAsset` (e.g. WMATIC) to `asset` (e.g. USDC). Has 6 decimals.
    function _borrowToAsset(uint256 borrowChainlinkPrice, uint256 amountB) internal pure returns (uint256 assets) {
        assets = borrowChainlinkPrice.mulWadDown(amountB) / 1e2;
    }

    /// @notice Convert `asset` (e.g. USDC) to `borrowAsset` (e.g. WMATIC). Has 18 decimals.
    function _assetToBorrow(uint256 borrowChainlinkPrice, uint256 amountA) internal pure returns (uint256 borrows) {
        borrows = (amountA * 1e2).divWadDown(borrowChainlinkPrice);
    }

    /// @notice Get pro rata underlying assets (USDC, WMATIC) amounts from sushiswap lp token amount
    function _getSushiLpUnderlyingAmounts(uint256 lpTokenAmount)
        internal
        view
        returns (uint256 assets, uint256 borrows)
    {
        assets = lpTokenAmount.mulDivDown(asset.balanceOf(address(abPair)), abPair.totalSupply());
        borrows = lpTokenAmount.mulDivDown(borrowAsset.balanceOf(address(abPair)), abPair.totalSupply());
    }

    function _totalLockedValue(bool useSpotPrice) public view returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfMatic + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens

        // Using spot price from sushiswap for calculating TVL.
        uint256 borrowPrice = useSpotPrice ? _sushiPriceOfBorrow() : _chainlinkPriceOfBorrow();

        // Asset value of underlying matic
        uint256 assetsMatic = _borrowToAsset(borrowPrice, borrowAsset.balanceOf(address(this)));

        // Underlying value of sushi LP tokens
        uint256 miniChefStakedAmount = miniChef.userInfo(miniChefPid, address(this)).amount;
        uint256 sushiTotalStakedAmount = abPair.balanceOf(address(this)) + miniChefStakedAmount;
        (uint256 sushiUnderlyingAssets, uint256 sushiUnderlyingBorrows) =
            _getSushiLpUnderlyingAmounts(sushiTotalStakedAmount);
        uint256 sushiLpValue = sushiUnderlyingAssets + _borrowToAsset(borrowPrice, sushiUnderlyingBorrows);

        // Asset value of debt
        uint256 assetsDebt = _borrowToAsset(borrowPrice, debtToken.balanceOf(address(this)));

        return balanceOfAsset() + assetsMatic + aToken.balanceOf(address(this)) + sushiLpValue - assetsDebt;
    }

    function totalLockedValue() public view override returns (uint256) {
        return _totalLockedValue(true);
    }

    function totalLockedValue(bool useSpotPrice) public view returns (uint256) {
        return _totalLockedValue(useSpotPrice);
    }

    uint32 public currentPosition;
    bool public canStartNewPos;

    IMiniChef public miniChef;
    uint256 public miniChefPid;
    ERC20 public sushiToken;

    event PositionStart(
        uint32 indexed position,
        uint256 assetBalance,
        uint256 borrowPriceChainlink,
        uint256 borrowPriceSushi,
        uint256 timestamp
    );

    /// @notice Fixed point number describing the percentage of the position with which to go long. 1e18 = 1 = 100%
    uint256 public longPercentage;

    IUniswapV2Router02 public immutable router;
    /// @notice The address of the Uniswap Lp token (the asset-borrowAsset pair)
    ERC20 public immutable abPair;

    /// @notice The asset we want to borrow, e.g. WMATIC
    ERC20 public immutable borrowAsset;
    ILendingPool immutable lendingPool;
    /// @notice The asset we get when we borrow our `borrowAsset` from aave
    ERC20 public immutable debtToken;
    /// @notice The asset we get deposit `asset` into aave
    ERC20 public immutable aToken;

    /// @notice Gives ratio of vault asset to borrow asset, e.g. WMATIC/USD (assuming usdc = usd)
    AggregatorV3Interface immutable borrowAssetFeed;

    event MetricInfo(
        uint256 indexed position,
        uint256 step,
        uint256 assetBalance,
        uint256 borrowBalance,
        uint256 abPairBalance,
        uint256 aTokenBalance,
        uint256 debtTokenBalance,
        uint256 sushiBalance,
        uint256 miniChefStakedAmount
    );

    function _exportMetricInfo(uint256 step) internal {
        emit MetricInfo(
            currentPosition,
            step,
            asset.balanceOf(address(this)),
            borrowAsset.balanceOf(address(this)),
            abPair.balanceOf(address(this)),
            aToken.balanceOf(address(this)),
            debtToken.balanceOf(address(this)),
            sushiToken.balanceOf(address(this)),
            miniChef.userInfo(miniChefPid, address(this)).amount
            );
    }

    function startPosition(uint256 slippageToleranceBps) external onlyRole(STRATEGIST_ROLE) {
        // Set position metadata
        require(canStartNewPos, "DNLP: position is active");
        currentPosition += 1;
        canStartNewPos = false;

        uint256 initTVL = totalLockedValue();
        uint256 borrowPrice = _chainlinkPriceOfBorrow();
        emit PositionStart(currentPosition, initTVL, borrowPrice, _sushiPriceOfBorrow(), block.timestamp);

        _exportMetricInfo(1);

        // Scope to avoid stack too deep error. See https://maticereum.stackexchange.com/a/84378
        // Some amount of the assets will be used to buy matic at the end of this scope.
        {
            // USDC -> WMATIC path
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);
            uint256 assetsToBorrow = asset.balanceOf(address(this)).mulWadDown(longPercentage);
            uint256 borrowOutMin = _assetToBorrow(borrowPrice, assetsToBorrow).slippageDown(slippageToleranceBps);
            if (assetsToBorrow > 0) {
                router.swapExactTokensForTokens({
                    amountIn: assetsToBorrow,
                    amountOutMin: borrowOutMin,
                    path: path,
                    to: address(this),
                    deadline: block.timestamp
                });
            }
        }
        uint256 swappedBorrowAmount = borrowAsset.balanceOf(address(this));

        _exportMetricInfo(2);

        // Deposit asset in aave. Then borrow Matic at 75% (88% liquidation threshold and 85.5% max LTV)
        // If x is amount we want to deposit into aave .75x = Total - x => 1.75x = Total => x = Total / 1.75 => Total * 4/7
        uint256 assetsToDeposit = asset.balanceOf(address(this)).mulDivDown(4, 7);
        if (assetsToDeposit > 0) {
            lendingPool.deposit({
                asset: address(asset),
                amount: assetsToDeposit,
                onBehalfOf: address(this),
                referralCode: 0
            });
        }

        _exportMetricInfo(3);

        // https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#borrow
        uint256 borrowAmount = _assetToBorrow(borrowPrice, assetsToDeposit).mulDivDown(3, 4);
        if (borrowAmount > 0) {
            lendingPool.borrow({
                asset: address(borrowAsset),
                amount: borrowAmount,
                interestRateMode: 2,
                referralCode: 0,
                onBehalfOf: address(this)
            });
        }

        _exportMetricInfo(4);

        // Provide liquidity on uniswap
        uint256 assetsBalance = asset.balanceOf(address(this));
        uint256 borrowBalance = borrowAsset.balanceOf(address(this)) - swappedBorrowAmount;
        uint256 assetsInMin = assetsBalance.slippageDown(slippageToleranceBps);
        uint256 borrowInMin = assetsBalance.slippageDown(slippageToleranceBps);

        router.addLiquidity({
            tokenA: address(asset),
            tokenB: address(borrowAsset),
            amountADesired: assetsBalance,
            amountBDesired: borrowBalance,
            amountAMin: assetsInMin,
            amountBMin: borrowInMin,
            to: address(this),
            deadline: block.timestamp
        });

        _exportMetricInfo(5);

        // Deposit to MasterChef for additional SUSHI rewards.
        miniChef.deposit(miniChefPid, abPair.balanceOf(address(this)), address(this));

        _exportMetricInfo(6);
    }

    /// @dev This strategy should be put at the end of the WQ so that we rarely divest from it. Divestment
    /// ideally occurs when the strategy does not have an open position
    function _divest(uint256 assets) internal override returns (uint256) {
        // Totally unwind the position
        if (!canStartNewPos) _endPosition(MAX_BPS / 20); // 5% slippage tolerance.

        uint256 amountToSend = Math.min(assets, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        // Return the given amount
        return amountToSend;
    }

    event PositionEnd(
        uint32 indexed position,
        uint256 assetBalance,
        uint256 borrowPriceChainlink,
        uint256 borrowPriceSushi,
        uint256 timestamp
    );

    function endPosition(uint256 slippageToleranceBps) external onlyRole(STRATEGIST_ROLE) {
        _endPosition(slippageToleranceBps);
    }

    function claimRewardsAndEndPosition(uint256 slippageToleranceBps) external onlyRole(STRATEGIST_ROLE) {
        _claimRewards(slippageToleranceBps);
        _endPosition(slippageToleranceBps);
    }

    function _endPosition(uint256 slippageToleranceBps) internal {
        // Set position metadata
        require(!canStartNewPos, "DNLP: position is inactive");
        canStartNewPos = true;

        _exportMetricInfo(7);

        uint256 borrowPrice = _chainlinkPriceOfBorrow();

        uint256 depositedSLPAmount = miniChef.userInfo(miniChefPid, address(this)).amount;
        miniChef.withdraw(miniChefPid, depositedSLPAmount, address(this));

        _exportMetricInfo(8);

        // Remove liquidity
        // a = usdc, b = WMATIC
        uint256 abPairBalance = abPair.balanceOf(address(this));
        (uint256 underlyingAssets, uint256 underlyingBorrows) = _getSushiLpUnderlyingAmounts(abPairBalance);
        router.removeLiquidity({
            tokenA: address(asset),
            tokenB: address(borrowAsset),
            liquidity: abPairBalance,
            amountAMin: underlyingAssets.slippageDown(slippageToleranceBps),
            amountBMin: underlyingBorrows.slippageDown(slippageToleranceBps),
            to: address(this),
            deadline: block.timestamp
        });

        _exportMetricInfo(9);

        // Buy enough matic to pay back debt
        uint256 debt = debtToken.balanceOf(address(this));
        uint256 bBal = borrowAsset.balanceOf(address(this));
        // Either we buy matic or sell matic. If we need to buy then borrowToBuy will be
        // positive and borrowToSell will be zero and vice versa.
        uint256 borrowToBuy = debt > bBal ? debt - bBal : 0;
        uint256 borrowToSell = bBal > debt ? bBal - debt : 0;

        if (borrowToBuy > 0) {
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);

            router.swapTokensForExactTokens({
                amountOut: borrowToBuy,
                amountInMax: _borrowToAsset(borrowPrice, borrowToBuy).slippageUp(slippageToleranceBps),
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }
        if (borrowToSell > 0) {
            address[] memory path = new address[](2);
            path[0] = address(borrowAsset);
            path[1] = address(asset);
            router.swapExactTokensForTokens({
                amountIn: borrowToSell,
                amountOutMin: _borrowToAsset(borrowPrice, borrowToSell).slippageDown(slippageToleranceBps),
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }

        _exportMetricInfo(10);

        // Repay debt
        lendingPool.repay({asset: address(borrowAsset), amount: debt, rateMode: 2, onBehalfOf: address(this)});

        _exportMetricInfo(11);

        // Withdraw from aave
        lendingPool.withdraw({asset: address(asset), amount: aToken.balanceOf(address(this)), to: address(this)});

        _exportMetricInfo(12);

        emit PositionEnd(
            currentPosition, asset.balanceOf(address(this)), borrowPrice, _sushiPriceOfBorrow(), block.timestamp
            );
    }

    function claimRewards(uint256 slippageToleranceBps) external onlyRole(STRATEGIST_ROLE) {
        _claimRewards(slippageToleranceBps);
    }

    function _claimRewards(uint256 slippageToleranceBps) internal {
        // Sell SUSHI tokens to USDC
        uint256 sushiBalance = sushiToken.balanceOf(address(this));
        if (sushiBalance > 0) {
            address[] memory path = new address[](3);
            path[0] = address(sushiToken);
            path[1] = address(borrowAsset);
            path[2] = address(asset);

            uint256[] memory amounts = router.getAmountsOut({amountIn: sushiBalance, path: path});
            uint256 minAmountOut = amounts[2].slippageDown(slippageToleranceBps);
            router.swapExactTokensForTokens({
                amountIn: sushiBalance,
                amountOutMin: minAmountOut,
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }
    }
}
