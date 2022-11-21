// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
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
import {BaseStrategy} from "../BaseStrategy.sol";
import {SlippageUtils} from "../libs/SlippageUtils.sol";

contract DeltaNeutralLpV3 is BaseStrategy, AccessControl {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    constructor(
        BaseVault _vault,
        uint256 _slippageTolerance,
        ILendingPoolAddressesProviderRegistry _registry,
        ERC20 _borrowAsset,
        AggregatorV3Interface _borrowAssetFeed,
        ISwapRouter _router,
        INonfungiblePositionManager _lpManager,
        IUniswapV3Pool _pool
    ) BaseStrategy(_vault) {
        _grantRole(DEFAULT_ADMIN_ROLE, vault.governance());
        _grantRole(STRATEGIST_ROLE, vault.governance());

        canStartNewPos = true;
        slippageTolerance = _slippageTolerance;

        borrowAsset = _borrowAsset;
        borrowAssetFeed = _borrowAssetFeed;

        router = _router;
        lpManager = _lpManager;
        pool = _pool;
        poolFee = _pool.fee();
        token0 = pool.token0();
        token1 = pool.token1();

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

        // Deploy the PositionValue contract
        /* solhint-disable no-inline-assembly */
        bytes memory posValCode =
            hex"608060405234801561001057600080fd5b50610d63806100206000396000f3fe608060405234801561001057600080fd5b506004361061002b5760003560e01c80635b6dc09214610030575b600080fd5b6100666004803603606081101561004657600080fd5b506001600160a01b0381358116916020810135916040909101351661007f565b6040805192835260208301919091528051918290030190f35b60008061008d858585610099565b91509150935093915050565b6000806000806100aa8787876100cc565b915091506000806100bb8989610188565b940195505050019050935093915050565b6000806000806000876001600160a01b03166399fbab88886040518263ffffffff1660e01b8152600401808281526020019150506101806040518083038186803b15801561011957600080fd5b505afa15801561012d573d6000803e3d6000fd5b505050506040513d61018081101561014457600080fd5b5060a081015160c082015160e09092015190945090925090506101798661016a8561033b565b6101738561033b565b8461066d565b94509450505050935093915050565b6000806000806000806000806000806000808d6001600160a01b03166399fbab888e6040518263ffffffff1660e01b8152600401808281526020019150506101806040518083038186803b1580156101df57600080fd5b505afa1580156101f3573d6000803e3d6000fd5b505050506040513d61018081101561020a57600080fd5b810190808051906020019092919080519060200190929190805190602001909291908051906020019092919080519060200190929190805190602001909291908051906020019092919080519060200190929190805190602001909291908051906020019092919080519060200190929190805190602001909291905050506001600160801b03169b506001600160801b03169b509b509b509b509b509b509b509b509b5050506103268e6040518061014001604052808d6001600160a01b031681526020018c6001600160a01b031681526020018b62ffffff1681526020018a60020b81526020018960020b8152602001886001600160801b0316815260200187815260200186815260200185815260200184815250610709565b9b509b50505050505050505050509250929050565b60008060008360020b12610352578260020b61035a565b8260020b6000035b9050620d89e8811115610398576040805162461bcd60e51b81526020600482015260016024820152601560fa1b604482015290519081900360640190fd5b6000600182166103ac57600160801b6103be565b6ffffcb933bd6fad37aa2d162d1a5940015b70ffffffffffffffffffffffffffffffffff16905060028216156103f2576ffff97272373d413259a46990580e213a0260801c5b6004821615610411576ffff2e50f5f656932ef12357cf3c7fdcc0260801c5b6008821615610430576fffe5caca7e10e4e61c3624eaa0941cd00260801c5b601082161561044f576fffcb9843d60f6159c9db58835c9266440260801c5b602082161561046e576fff973b41fa98c081472e6896dfb254c00260801c5b604082161561048d576fff2ea16466c96a3843ec78b326b528610260801c5b60808216156104ac576ffe5dee046a99a2a811c461f1969c30530260801c5b6101008216156104cc576ffcbe86c7900a88aedcffc83b479aa3a40260801c5b6102008216156104ec576ff987a7253ac413176f2b074cf7815e540260801c5b61040082161561050c576ff3392b0822b70005940c7a398e4b70f30260801c5b61080082161561052c576fe7159475a2c29b7443b29c7fa6e889d90260801c5b61100082161561054c576fd097f3bdfd2022b8845ad8f792aa58250260801c5b61200082161561056c576fa9f746462d870fdf8a65dc1f90e061e50260801c5b61400082161561058c576f70d869a156d2a1b890bb3df62baf32f70260801c5b6180008216156105ac576f31be135f97d08fd981231505542fcfa60260801c5b620100008216156105cd576f09aa508b5b7a84e1c677de54f3e99bc90260801c5b620200008216156105ed576e5d6af8dedb81196699c329225ee6040260801c5b6204000082161561060c576d2216e584f5fa1ea926041bedfe980260801c5b62080000821615610629576b048a170391f7dc42444e8fa20260801c5b60008460020b131561064457806000198161064057fe5b0490505b64010000000081061561065857600161065b565b60005b60ff16602082901c0192505050919050565b600080836001600160a01b0316856001600160a01b0316111561068e579293925b846001600160a01b0316866001600160a01b0316116106b9576106b2858585610827565b9150610700565b836001600160a01b0316866001600160a01b031610156106f2576106de868585610827565b91506106eb858785610892565b9050610700565b6106fd858585610892565b90505b94509492505050565b6000806000806107c46107b5876001600160a01b031663c45a01556040518163ffffffff1660e01b815260040160206040518083038186803b15801561074e57600080fd5b505afa158015610762573d6000803e3d6000fd5b505050506040513d602081101561077857600080fd5b50516040805160608101825289516001600160a01b03908116825260208b810151909116908201528982015162ffffff16918101919091526108dd565b866060015187608001516109c1565b915091508461010001516107f08660c0015184038760a001516001600160801b0316600160801b610c7e565b01935084610120015161081b8660e0015183038760a001516001600160801b0316600160801b610c7e565b01925050509250929050565b6000826001600160a01b0316846001600160a01b03161115610847579192915b836001600160a01b0316610880606060ff16846001600160801b0316901b8686036001600160a01b0316866001600160a01b0316610c7e565b8161088757fe5b0490505b9392505050565b6000826001600160a01b0316846001600160a01b031611156108b2579192915b6108d5826001600160801b03168585036001600160a01b0316600160601b610c7e565b949350505050565b600081602001516001600160a01b031682600001516001600160a01b03161061090557600080fd5b50805160208083015160409384015184516001600160a01b0394851681850152939091168385015262ffffff166060808401919091528351808403820181526080840185528051908301206001600160f81b031960a085015294901b6bffffffffffffffffffffffff191660a183015260b58201939093527fe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b5460d5808301919091528251808303909101815260f5909101909152805191012090565b6000806000856001600160a01b0316633850c7bd6040518163ffffffff1660e01b815260040160e06040518083038186803b1580156109ff57600080fd5b505afa158015610a13573d6000803e3d6000fd5b505050506040513d60e0811015610a2957600080fd5b50602001516040805163f30dba9360e01b8152600288900b6004820152905191925060009182916001600160a01b038a169163f30dba939160248082019261010092909190829003018186803b158015610a8257600080fd5b505afa158015610a96573d6000803e3d6000fd5b505050506040513d610100811015610aad57600080fd5b50604080820151606090920151815163f30dba9360e01b815260028a900b60048201529151929450925060009182916001600160a01b038c169163f30dba939160248082019261010092909190829003018186803b158015610b0e57600080fd5b505afa158015610b22573d6000803e3d6000fd5b505050506040513d610100811015610b3957600080fd5b5060408101516060909101519092509050600289810b9086900b1215610b685781840396508083039550610c71565b8760020b8560020b1215610c665760008a6001600160a01b031663f30583996040518163ffffffff1660e01b815260040160206040518083038186803b158015610bb157600080fd5b505afa158015610bc5573d6000803e3d6000fd5b505050506040513d6020811015610bdb57600080fd5b505160408051634614131960e01b815290519192506000916001600160a01b038e16916346141319916004808301926020929190829003018186803b158015610c2357600080fd5b505afa158015610c37573d6000803e3d6000fd5b505050506040513d6020811015610c4d57600080fd5b5051918690038490039850508390038190039550610c71565b838203965082810395505b5050505050935093915050565b6000808060001985870986860292508281109083900303905080610cb45760008411610ca957600080fd5b50829004905061088b565b808411610cc057600080fd5b6000848688096000868103871696879004966002600389028118808a02820302808a02820302808a02820302808a02820302808a02820302808a0290910302918190038190046001018684119095039490940291909403929092049190911791909102915050939250505056fea2646970667358221220de37b8e840d601c36d0b6b85a17d86c86b8948ad517df76085fa011f2a0dcdb964736f6c63430007060033";
        address positionVal;
        assembly {
            // posValCode =  32 byte length | actual code
            positionVal := create(0, add(posValCode, 0x20), mload(posValCode))
        }
        require(positionVal.code.length > 0, "DNLPV3: PositionVal failed");
        positionValue = IUniPositionValue(positionVal);
    }

    /// @notice Convert `borrowAsset` (e.g. MATIC) to `asset` (e.g. USDC)
    function _borrowToAsset(uint256 amountB, uint256 clPrice) internal pure returns (uint256 assets) {
        // The first divisition gets rid of the decimals of wmatic. The second converts dollars to usdc
        // TODO: make this work for any set of decimals
        assets = amountB.mulWadDown(clPrice) / 1e2;
    }

    function _assetToBorrow(uint256 assets, uint256 clPrice) internal pure returns (uint256 borrows) {
        borrows = (assets * 1e2).divWadDown(clPrice);
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
        uint256 borrowPrice,
        int24 tickLow,
        int24 tickHigh,
        uint256 assetsToUni,
        uint256 borrowsToUni,
        uint256 timestamp
    );

    uint256 public slippageTolerance;

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
    IUniPositionValue immutable positionValue;

    /// @notice The asset we want to borrow, e.g. WMATIC
    ERC20 public immutable borrowAsset;
    ILendingPool immutable lendingPool;
    /// @notice The asset we get when we borrow our `borrowAsset` from aave
    ERC20 public immutable debtToken;
    /// @notice The asset we get deposit `asset` into aave
    ERC20 public immutable aToken;

    /// @notice Gives ratio of vault asset to borrow asset, e.g. WMATIC/USD (assuming usdc = usd)
    AggregatorV3Interface immutable borrowAssetFeed;

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

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
            borrowPrice: borrowPrice,
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
        uint256 borrowPrice,
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

        // Buy enough matic to pay back debt
        uint256 debt;
        uint256 assetsOrBorrowsSold;
        uint256 assetsOrBorrowsReceived;
        bool assetSold;
        {
            debt = debtToken.balanceOf(address(this));
            uint256 bBal = borrowAsset.balanceOf(address(this));
            uint256 maticToBuy = debt > bBal ? debt - bBal : 0;
            uint256 maticToSell = bBal > debt ? bBal - debt : 0;

            if (maticToBuy > 0) {
                (assetsOrBorrowsSold, assetsOrBorrowsReceived) =
                    _swapExactOutputSingle(asset, borrowAsset, maticToBuy, slippageBps);
            }
            if (maticToSell > 0) {
                (assetsOrBorrowsSold, assetsOrBorrowsReceived) =
                    _swapExactSingle(borrowAsset, asset, maticToSell, slippageBps);
            }
            assetSold = maticToBuy > 0;
        }

        // Repay debt
        lendingPool.repay({asset: address(borrowAsset), amount: debt, rateMode: 2, onBehalfOf: address(this)});

        // Withdrawal from aave
        uint256 assetCollateral = aToken.balanceOf(address(this));
        lendingPool.withdraw({asset: address(asset), amount: assetCollateral, to: address(this)});

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
        emit PositionEnd({
            position: currentPosition,
            assetsFromUni: assetsFromUni,
            borrowsFromUni: borrowsFromUni,
            assetFees: assetFees,
            borrowFees: borrowFees,
            borrowPrice: _getPrice(),
            assetSold: assetSold,
            assetsOrBorrowsSold: assetsOrBorrowsSold,
            assetsOrBorrowsReceived: assetsOrBorrowsReceived,
            assetCollateral: assetCollateral,
            borrowDebtPaid: debt,
            timestamp: block.timestamp
        });
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
