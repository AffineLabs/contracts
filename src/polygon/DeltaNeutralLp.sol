// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
        IUniswapV2Router02 _router,
        IUniswapV2Factory _factory
    ) BaseStrategy(_vault) {
        canStartNewPos = true;
        slippageTolerance = _slippageTolerance;
        longPercentage = _longPct;

        borrowAsset = _borrowAsset;
        borrowAssetFeed = _borrowAssetFeed;

        router = _router;
        abPair = ERC20(_factory.getPair(address(asset), address(borrowAsset)));

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
        // To remove liquidity
        abPair.safeApprove(address(_router), type(uint256).max);
    }

    /// @notice Convert `borrowAsset` (e.g. MATIC) to `asset` (e.g. USDC)
    function _borrowToAsset(uint256 amountB) internal view returns (uint256 assets) {
        if (amountB == 0) {
            assets = 0;
            return assets;
        }

        address[] memory path = new address[](2);
        path[0] = address(borrowAsset);
        path[1] = address(asset);

        uint256[] memory amounts = router.getAmountsOut({amountIn: amountB, path: path});
        assets = amounts[1];
    }

    function totalLockedValue() public view override returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfMatic + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens

        uint256 assetsMatic = _borrowToAsset(borrowAsset.balanceOf(address(this)));

        uint256 assetsLP =
            abPair.balanceOf(address(this)).mulDivDown(asset.balanceOf(address(abPair)) * 2, abPair.totalSupply());

        uint256 assetsDebt = _borrowToAsset(debtToken.balanceOf(address(this)));
        return balanceOfAsset() + assetsMatic + aToken.balanceOf(address(this)) + assetsLP - assetsDebt;
    }

    uint32 public currentPosition;
    bool public canStartNewPos;

    event PositionStart(uint32 indexed position, uint256 assetBalance, uint256 chainlinkRoundId, uint256 timestamp);

    uint256 public slippageTolerance;
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

    function startPosition() external onlyOwner {
        // Set position metadata
        require(canStartNewPos, "DNLP: position is active");
        uint32 newPositionId = currentPosition + 1;
        currentPosition = newPositionId;
        canStartNewPos = false;

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
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = borrowAssetFeed.latestRoundData();
        require(price > 0, "DNLP: price <= 0");
        require(answeredInRound >= roundId, "DNLP: stale data");
        require(timestamp != 0, "DNLP: round not done");

        emit PositionStart(newPositionId, assets, roundId, block.timestamp);

        // https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#borrow
        // assetsToDeposit has price uints `asset`, price has units `asset / borrowAsset` ratio. so we divide by price
        // Scaling `asset` to 8 decimals since chainlink provides 8: https://docs.chain.link/docs/data-feeds/price-feeds/
        // TODO: handle both cases (assetDecimals > priceDecimals as well)
        uint256 borrowAssetsDeposited = (assetsToDeposit * 1e2 * 1e18) / (uint256(price));
        lendingPool.borrow({
            asset: address(borrowAsset),
            amount: borrowAssetsDeposited.mulDivDown(3, 4),
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: address(this)
        });

        // Provide liquidity on uniswap
        // TODO: make slippage parameterizable by caller
        uint256 bBal = borrowAsset.balanceOf(address(this));
        uint256 aBal = assets - assetsToMatic - assetsToDeposit;
        router.addLiquidity({
            tokenA: address(asset),
            tokenB: address(borrowAsset),
            amountADesired: aBal,
            amountBDesired: bBal,
            amountAMin: aBal.mulDivDown(98, 100),
            amountBMin: bBal.mulDivDown(98, 100),
            to: address(this),
            deadline: block.timestamp
        });

        // Buy Matic. The strat now holds only lp tokens and a little bit of matic
        address[] memory path = new address[](2);
        path[0] = address(asset);
        path[1] = address(borrowAsset);

        router.swapExactTokensForTokens({
            amountIn: assetsToMatic,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
    }

    /// @dev This strategy should be put at the end of the WQ so that we rarely divest from it. Divestment
    /// ideally occurs when the strategy does not have an open position
    function _divest(uint256 assets) internal override returns (uint256) {
        // Totally unwind the position
        if (!canStartNewPos) _endPosition();

        uint256 amountToSend = Math.min(assets, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        // Return the given amount
        return amountToSend;
    }

    event PositionEnd(uint32 indexed position, uint256 assetBalance, uint256 timestamp);

    function endPosition() external onlyOwner {
        _endPosition();
    }

    function _endPosition() internal {
        // Set position metadata
        require(!canStartNewPos, "DNLP: position is inactive");
        canStartNewPos = true;

        // Remove liquidity
        // TODO: handle slippage
        router.removeLiquidity({
            tokenA: address(asset),
            tokenB: address(borrowAsset),
            liquidity: abPair.balanceOf(address(this)),
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });

        // Buy enough matic to pay back debt
        uint256 debt = debtToken.balanceOf(address(this));
        uint256 bBal = borrowAsset.balanceOf(address(this));
        uint256 maticToBuy = debt > bBal ? debt - bBal : 0;
        uint256 maticToSell = bBal > debt ? bBal - debt : 0;

        if (maticToBuy > 0) {
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);

            router.swapTokensForExactTokens({
                amountOut: maticToBuy,
                amountInMax: asset.balanceOf(address(this)),
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }
        if (maticToSell > 0) {
            address[] memory path = new address[](2);
            path[0] = address(borrowAsset);
            path[1] = address(asset);
            router.swapExactTokensForTokens({
                amountIn: maticToSell,
                amountOutMin: 0,
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }

        // Repay debt
        lendingPool.repay({asset: address(borrowAsset), amount: debt, rateMode: 2, onBehalfOf: address(this)});

        // Withdraw from aave
        lendingPool.withdraw({asset: address(asset), amount: aToken.balanceOf(address(this)), to: address(this)});

        emit PositionEnd(currentPosition, asset.balanceOf(address(this)), block.timestamp);
    }
}