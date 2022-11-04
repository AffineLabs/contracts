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
import {IMasterChef} from "../interfaces/sushiswap/IMasterChef.sol";

contract DeltaNeutralLp is BaseStrategy, AccessControl {
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
        IMasterChef _masterChef,
        uint256 _masterChefPid
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

        masterChef = _masterChef;
        masterChefPid = _masterChefPid;
        sushiToken = ERC20(_masterChef.sushi());

        // Depositing/withdrawing/repaying debt from lendingPool
        asset.safeApprove(address(lendingPool), type(uint256).max);
        aToken.safeApprove(address(lendingPool), type(uint256).max);
        borrowAsset.safeApprove(address(lendingPool), type(uint256).max);

        // To trade usdc/eth
        asset.safeApprove(address(_router), type(uint256).max);
        borrowAsset.safeApprove(address(_router), type(uint256).max);
        // To remove liquidity
        abPair.safeApprove(address(_router), type(uint256).max);
        // For staging SLP token
        abPair.safeApprove(address(_masterChef), type(uint256).max);
        // For trading shushi/usdc
        sushiToken.safeApprove(address(_router), type(uint256).max);
    }

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST");
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Get prices of WETH -> USDC (borrowToAssetPrice) and USDC -> WETH (assetToBorrowPrice) with chainlink round id.
    function _pricesFromChainlink()
        internal
        view
        returns (uint256 borrowToAssetPrice, uint256 assetToBorrowPrice, uint80 priceRoundId)
    {
        (uint80 roundId, int256 borrowPrice,, uint256 timestamp, uint80 answeredInRound) =
            borrowAssetFeed.latestRoundData();
        require(borrowPrice > 0, "DNLP: price <= 0");
        require(answeredInRound >= roundId, "DNLP: stale data");
        require(timestamp != 0, "DNLP: round not done");
        borrowToAssetPrice = uint256(borrowPrice) / 1e2; // Convert 8 decimals to 6 decimals
        assetToBorrowPrice = 1e18 / borrowToAssetPrice;
        priceRoundId = roundId;
    }

    /// @notice Convert `borrowAsset` (e.g. WETH) to `asset` (e.g. USDC)
    function _borrowToAsset(uint256 amountB) internal view returns (uint256 assets) {
        (uint256 borrowToAssetPrice,,) = _pricesFromChainlink();
        return borrowToAssetPrice.mulWadDown(amountB);
    }

    /// @notice Convert `asset` (e.g. USDC) to `borrowAsset` (e.g. WETH)
    function _assetToBorrow(uint256 amountA) internal view returns (uint256 borrows) {
        (, uint256 assetToBorrowPrice,) = _pricesFromChainlink();
        return assetToBorrowPrice.mulDivDown(amountA, 1e6);
    }

    /// @notice Get pro rata underlying assets (USDC, WETH) amounts from sushiswap lp token amount
    function _getShushiLpUnderlyingAmounts(uint256 lpTokenAmount)
        internal
        view
        returns (uint256 assets, uint256 borrows)
    {
        assets = lpTokenAmount.mulDivDown(asset.balanceOf(address(abPair)), abPair.totalSupply());
        borrows = lpTokenAmount.mulDivDown(borrowAsset.balanceOf(address(abPair)), abPair.totalSupply());
    }

    function totalLockedValue() public view override returns (uint256) {
        // The below are all in units of `asset`
        // balanceOfAsset + balanceOfEth + aToken value + Uni Lp value - debt
        // lp tokens * (total assets) / total lp tokens

        // Asset value of underlying eth
        uint256 assetsEth = _borrowToAsset(borrowAsset.balanceOf(address(this)));

        // Underlying value of sushi LP tokens
        uint256 masterChefStakedAmount = masterChef.userInfo(masterChefPid, address(this)).amount;
        uint256 sushiTotalStakedAmount = abPair.balanceOf(address(this)) + masterChefStakedAmount;
        (uint256 sushiUnderlyingAssets, uint256 sushiUnderlyingBorrows) =
            _getShushiLpUnderlyingAmounts(sushiTotalStakedAmount);
        uint256 sushiLpValue = sushiUnderlyingAssets + _borrowToAsset(sushiUnderlyingBorrows);

        // Asset value of debt
        uint256 assetsDebt = _borrowToAsset(debtToken.balanceOf(address(this)));

        return balanceOfAsset() + assetsEth + aToken.balanceOf(address(this)) + sushiLpValue - assetsDebt;
    }

    uint32 public currentPosition;
    bool public canStartNewPos;

    IMasterChef public masterChef;
    uint256 public masterChefPid;
    ERC20 public sushiToken;

    event PositionStart(uint32 indexed position, uint256 assetBalance, uint256 chainlinkRoundId, uint256 timestamp);

    /// @notice Fixed point number describing the percentage of the position with which to go long. 1e18 = 1 = 100%
    uint256 public longPercentage;

    IUniswapV2Router02 public immutable router;
    /// @notice The address of the Uniswap Lp token (the asset-borrowAsset pair)
    ERC20 public immutable abPair;

    /// @notice The asset we want to borrow, e.g. WETH
    ERC20 public immutable borrowAsset;
    ILendingPool immutable lendingPool;
    /// @notice The asset we get when we borrow our `borrowAsset` from aave
    ERC20 public immutable debtToken;
    /// @notice The asset we get deposit `asset` into aave
    ERC20 public immutable aToken;

    /// @notice Gives ratio of vault asset to borrow asset, e.g. WETH/USD (assuming usdc = usd)
    AggregatorV3Interface immutable borrowAssetFeed;

    function startPosition(uint256 slippageToleranceBps) external onlyRole(STRATEGIST_ROLE) {
        uint256 initTVL = totalLockedValue();
        // Set position metadata
        require(canStartNewPos, "DNLP: position is active");
        currentPosition += 1;
        canStartNewPos = false;
        // Scope to avoid stack too deep error. See https://ethereum.stackexchange.com/a/84378
        {
            // Some amount of the assets will be used to buy eth at the end of this function
            uint256 assetsBalance = asset.balanceOf(address(this));
            uint256 borrowBalance = borrowAsset.balanceOf(address(this));

            // USDC -> WETH path
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);
            uint256 assetsToEth = assetsBalance.mulWadDown(longPercentage) - _borrowToAsset(borrowBalance);
            uint256 ethOutMin = _assetToBorrow(assetsToEth).slippageDown(slippageToleranceBps);
            if (assetsToEth > 0) {
                router.swapExactTokensForTokens({
                    amountIn: assetsToEth,
                    amountOutMin: ethOutMin,
                    path: path,
                    to: address(this),
                    deadline: block.timestamp
                });
            }
        }
        // Borrow Eth at 75% (88% liquidation threshold and 85.5% max LTV)
        // If x is amount we want to deposit into aave
        // .75x = Total - x => 1.75x = Total => x = Total / 1.75 => Total * 4/7
        // Deposit asset in aave
        {
            uint256 assetsBalance = asset.balanceOf(address(this));
            uint256 assetsToDeposit = assetsBalance.mulDivDown(4, 7);
            lendingPool.deposit({
                asset: address(asset),
                amount: assetsToDeposit,
                onBehalfOf: address(this),
                referralCode: 0
            });

            // Convert assetsToDeposit into `borrowAsset` (e.g. WETH) units
            (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) =
                borrowAssetFeed.latestRoundData();
            require(price > 0, "DNLP: price <= 0");
            require(answeredInRound >= roundId, "DNLP: stale data");
            require(timestamp != 0, "DNLP: round not done");

            emit PositionStart(currentPosition, initTVL, roundId, block.timestamp);

            // https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#borrow
            // assetsToDeposit has price uints `asset`, price has units `asset / borrowAsset` ratio. so we divide by price
            // Scaling `asset` to 8 decimals since chainlink provides 8: https://docs.chain.link/docs/data-feeds/price-feeds/
            // TODO: handle both cases (assetDecimals > priceDecimals as well)
            uint256 borrowAssetsDeposited = (assetsToDeposit * 1e2).divWadDown(uint256(price));
            lendingPool.borrow({
                asset: address(borrowAsset),
                amount: borrowAssetsDeposited.mulDivDown(3, 4),
                interestRateMode: 2,
                referralCode: 0,
                onBehalfOf: address(this)
            });
        }
        {
            // Provide liquidity on uniswap
            uint256 borrowBalance = borrowAsset.balanceOf(address(this));
            uint256 assetsBalance = asset.balanceOf(address(this));
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
        }

        // Deposit to MasterChef for additional SUSHI rewards.
        masterChef.deposit(masterChefPid, abPair.balanceOf(address(this)));
    }

    /// @dev This strategy should be put at the end of the WQ so that we rarely divest from it. Divestment
    /// ideally occurs when the strategy does not have an open position
    function _divest(uint256 assets) internal override returns (uint256) {
        // Totally unwind the position
        if (!canStartNewPos) _endPosition(MAX_BPS);

        uint256 amountToSend = Math.min(assets, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        // Return the given amount
        return amountToSend;
    }

    event PositionEnd(uint32 indexed position, uint256 assetBalance, uint256 timestamp);

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

        uint256 depositedSLPAmount = masterChef.userInfo(masterChefPid, address(this)).amount;
        masterChef.withdraw(masterChefPid, depositedSLPAmount);

        // Remove liquidity
        // abPair -> token0 or a = USDC, token1 or b = WETH.
        uint256 abPairBalance = abPair.balanceOf(address(this));
        (uint256 underlyingAssets, uint256 underlyingBorrows) = _getShushiLpUnderlyingAmounts(abPairBalance);
        router.removeLiquidity({
            tokenA: address(asset),
            tokenB: address(borrowAsset),
            liquidity: abPairBalance,
            amountAMin: underlyingAssets.slippageDown(slippageToleranceBps),
            amountBMin: underlyingBorrows.slippageDown(slippageToleranceBps),
            to: address(this),
            deadline: block.timestamp
        });

        // Buy enough eth to pay back debt
        uint256 debt = debtToken.balanceOf(address(this));
        uint256 bBal = borrowAsset.balanceOf(address(this));
        // Either we buy eth or sell eth. If we need to buy then ethToBuy will be
        // positive and ethToSell will be zero and vice versa.
        uint256 ethToBuy = debt > bBal ? debt - bBal : 0;
        uint256 ethToSell = bBal > debt ? bBal - debt : 0;

        if (ethToBuy > 0) {
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);

            router.swapTokensForExactTokens({
                amountOut: ethToBuy,
                amountInMax: _borrowToAsset(ethToBuy).slippageUp(slippageToleranceBps),
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }
        if (ethToSell > 0) {
            address[] memory path = new address[](2);
            path[0] = address(borrowAsset);
            path[1] = address(asset);
            router.swapExactTokensForTokens({
                amountIn: ethToSell,
                amountOutMin: _borrowToAsset(ethToSell).slippageDown(slippageToleranceBps),
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
