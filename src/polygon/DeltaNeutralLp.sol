// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import {ILendingPoolAddressesProvider} from "../interfaces/aave/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "../interfaces/aave/ILendingPool.sol";
import {IProtocolDataProvider} from "../interfaces/aave/IProtocolDataProvider.sol";
import {IUniLikeSwapRouter} from "../interfaces/IUniLikeSwapRouter.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

interface ILendingPoolAddressesProviderRegistry {
    function getAddressesProvidersList() external view returns (address[] memory);
}

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
        IUniLikeSwapRouter _router,
        IUniswapV2Factory _factory
    ) BaseStrategy(_vault) {
        canStartNewPos = true;
        slippageTolerance = _slippageTolerance;
        longPercentage = _longPct;

        borrowAssetFeed = _borrowAssetFeed;
        borrowAsset = _borrowAsset;

        address[] memory providers = _registry.getAddressesProvidersList();
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(providers[providers.length - 1]);
        lendingPool = ILendingPool(provider.getLendingPool());
        // TODO: Can lending pool provide both aToken and debtToken (variable)
        // https://docs.aave.com/developers/v/2.0/the-core-protocol/addresses-provider#getaddress
        (,, address _debtToken) = IProtocolDataProvider(provider.getAddress(bytes32(uint256(1))))
            .getReserveTokensAddresses(address(borrowAsset));
        debtToken = ERC20(_debtToken);
        aToken = ERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);

        router = _router;
        abPair = ERC20(_factory.getPair(address(asset), address(borrowAsset)));
        asset.safeApprove(address(_router), type(uint256).max);
        borrowAsset.safeApprove(address(_router), type(uint256).max);
    }

    function balanceOfAsset() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Convert `borrowAsset` (e.g. MATIC) to `asset` (e.g. USDC)
    function _borrowToAsset(uint256 amountB) internal view returns (uint256 assets) {
        address[] memory path = new address[](2);
        path[0] = address(borrowAsset);
        path[1] = address(asset);

        uint256[] memory amounts = router.getAmountsOut(amountB, path);
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

    IUniLikeSwapRouter public immutable router;
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
        lendingPool.deposit(address(asset), assetsToDeposit, address(this), 0);

        // Convert assetsToDeposit into `borrowAsset` (e.g. WMATIC) units
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = borrowAssetFeed.latestRoundData();
        require(price > 0, "Chainlink price <= 0");
        require(answeredInRound >= roundId, "Chainlink stale data");
        require(timestamp != 0, "Chainlink round not complete");

        // https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#borrow
        // assetsToDeposit has price uints `asset`, price has units `asset / borrowAsset` ratio. so we divide by price
        // Scaling price down since `asset` only has six decimals: https://docs.chain.link/docs/data-feeds/price-feeds/
        // TODO: handle both cases (assetDecimals > priceDecimals as well)
        // Also adding an extra 12 decimals to get to 18 decimals that WMATIC has
        uint256 borrowAssetsDeposited = (assetsToDeposit / (uint256(price) / 1e2)) * 1e12;

        lendingPool.borrow(address(borrowAsset), borrowAssetsDeposited.mulDivDown(3, 4), 2, 0, msg.sender);

        // Provide liquidity on uniswap
        // TODO: make slippage parameterizable by caller
        uint256 bBal = borrowAsset.balanceOf(address(this));
        uint256 aBal = assets - assetsToMatic - assetsToDeposit;
        router.addLiquidity(
            address(asset),
            address(borrowAsset),
            aBal,
            bBal,
            aBal.mulDivDown(98, 100),
            bBal.mulDivDown(98, 100),
            address(this),
            block.timestamp
        );

        // Buy Matic. The strat now holds only lp tokens and a little bit of matic
        address[] memory path = new address[](2);
        path[0] = address(asset);
        path[1] = address(borrowAsset);

        router.swapExactTokensForTokens(assetsToMatic, 0, path, address(this), block.timestamp);
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
        router.removeLiquidity(
            address(asset), address(borrowAsset), abPair.balanceOf(address(this)), 0, 0, address(this), block.timestamp
        );
        // Buy enough matic to pay back debt

        // Get current debt
        uint256 debt = debtToken.balanceOf(address(this));
        // Pay back debt
        uint256 bBal = borrowAsset.balanceOf(address(this));
        uint256 maticToBuy = debt - bBal > 0 ? debt - bBal : 0;
        uint256 maticToSell = bBal - debt > 0 ? bBal - debt : 0;

        if (maticToBuy > 0) {
            address[] memory path = new address[](2);
            path[0] = address(asset);
            path[1] = address(borrowAsset);

            router.swapTokensForExactTokens(
                maticToBuy, asset.balanceOf(address(this)), path, address(this), block.timestamp
            );
        }
        if (maticToSell > 0) {
            address[] memory path = new address[](2);
            path[0] = address(borrowAsset);
            path[1] = address(asset);
            router.swapExactTokensForTokens(maticToSell, 0, path, address(this), block.timestamp);
        }

        // Withdraw from aave
        lendingPool.withdraw(address(asset), aToken.balanceOf(address(this)), address(this));
    }
}
