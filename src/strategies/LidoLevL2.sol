// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {AffineVault, Strategy} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {IBalancerVault, IFlashLoanRecipient} from "src/interfaces/balancer.sol";
import {IWSTETH} from "src/interfaces/lido/IWSTETH.sol";
import {ICurvePool} from "src/interfaces/curve/ICurvePool.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

contract LidoLevL2 is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;
    using SafeTransferLib for IWSTETH;
    using FixedPointMathLib for uint256;

    IPool public constant AAVE = IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);

    constructor(uint256 _leverage, AffineVault _vault, address[] memory strategists)
        AccessStrategy(_vault, strategists)
    {
        leverage = _leverage;


        /* Deposit flow */
        // Trade wEth for wstETH (or equivalent, e.g. cbETH)
        WETH.safeApprove(address(CURVE), type(uint256).max);

        // Deposit wstETH in AAVE
        WSTETH.safeApprove(address(AAVE), type(uint256).max);


        // Withdrawals => Trade wstETH for ETH
        WSTETH.safeApprove(address(CURVE), type(uint256).max);
    
    }

    /*//////////////////////////////////////////////////////////////
                              FLASH LOANS
    //////////////////////////////////////////////////////////////*/

    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    enum LoanType {
        invest,
        divest
    }

    function receiveFlashLoan(
        ERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        require(msg.sender == address(BALANCER), "Staking: only balancer");

        uint256 ethBorrowed;
        uint256 daiBorrowed;
        (LoanType loan, address newStrategy) = abi.decode(userData, (LoanType, address));

        if (loan == LoanType.divest) {
            ethBorrowed = amounts[0];
            _endPosition(ethBorrowed);
        } else {
            ethBorrowed = amounts[0];
            _addToPosition(ethBorrowed);
        }

        // Payback Weth loan
        WETH.safeTransfer(address(BALANCER), ethBorrowed);
    }

    /*//////////////////////////////////////////////////////////////
                         INVESTMENT/DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice The leverage factor of the position in %. e.g. 150 would be 1.5x leverage.
    uint256 public immutable leverage;


    function addToPosition(uint256 size) external onlyRole(STRATEGIST_ROLE) {
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = size.mulDivUp(leverage, 100);
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LoanType.invest, address(0))
        });
    }

    function _addToPosition(uint256 ethBorrowed) internal {

        // Trade wETH to wstETH
        uint expectedWstETh = _ethToWstEth(ethBorrowed);
        // TODO: allow custom slippage params to be set
        uint wstEth = CURVE.exchange({x: 0, y: 1, dx: ethBorrowed, min_dy: expectedWstETh.mulDivDown(93, 100)});

        // Deposit wstETH in AAVE
        asset.safeApprove(address(lendingPool), type(uint256).max);
        AAVE.deposit(address(asset), wstEth, address(this), 0);


        // Borrow 90% of wstETH value in ETH using e-mode
        uint ethToBorrow =  _wstEthToEth(wstETH.mulDivDown(9, 10));
        AAVE.setUserEMode(1); // 1 = enabled
        AAVE.borrow(address(asset), ethToBorrow, 2, 0, address(this));
    
        // Convert ETH to wETH in order to pay back balancer flash loan of wETH
        WETH.deposit{value: ethToBorrow}();
    }

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    function _divest(uint256 amount) internal override returns (uint256) {
        (uint256 ethNeeded, uint256 daiNeeded) = _getDivestFlashLoanAmounts(amount);

        // Flashloan `ethNeeded` ETH from balancer, _endPosition gets called
        // Note that balancer actually token addresses to be sorted, so DAI must come before wETH
        uint256 arrSize = daiNeeded > 0 ? 2 : 1;
        ERC20[] memory tokens = new ERC20[](arrSize);
        if (daiNeeded > 0) {
            tokens[0] = DAI;
            tokens[1] = WETH;
        } else {
            tokens[0] = WETH;
        }
        uint256[] memory amounts = new uint256[](arrSize);
        if (daiNeeded > 0) {
            amounts[0] = daiNeeded;
            amounts[1] = ethNeeded;
        } else {
            amounts[0] = ethNeeded;
        }

        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LoanType.divest, address(0))
        });

        // Unlocked value is equal to my current wETH balance
        uint256 wethToSend = Math.min(amount, WETH.balanceOf(address(this)));
        WETH.safeTransfer(address(vault), wethToSend);
        return wethToSend;
    }

    function _getDivestFlashLoanAmounts(uint256 wethToDivest) internal returns (uint256 ethNeeded, uint256 daiNeeded) {
        uint256 tvl = totalLockedValue();
        uint256 ethDebt = CETH.borrowBalanceCurrent(address(this));
        ethNeeded = ethDebt.mulDivDown(wethToDivest, tvl);

        uint256 compDaiToRedeem = (CDAI.balanceOfUnderlying(address(this)).mulDivDown(wethToDivest, tvl));
        (, uint256 makerDai) = VAT.urns(ILK, MAKER.urns(cdpId));
        uint256 makerDaiToPay = makerDai.mulDivDown(wethToDivest, tvl);

        // Maker debt and comp collateral may diverge over time. Flashloan DAI if need to pay same percentage
        // of maker debt as we pay of compound debt
        // stETH will be traded to DAI to pay back this flashloan, so we need to set a min amount to make sure the trade succeeds
        if (makerDaiToPay > compDaiToRedeem && makerDaiToPay - compDaiToRedeem > 0.01e18) {
            daiNeeded = makerDaiToPay - compDaiToRedeem;
        }
    }

    function _endPosition(uint256 ethBorrowed, uint256 daiBorrowed) internal {
        // Pay debt in compound
        uint256 ethDebt = CETH.borrowBalanceCurrent(address(this));
        WETH.withdraw(ethBorrowed);

        CETH.repayBorrow{value: ethBorrowed}();
        uint256 daiToRedeem = CDAI.balanceOfUnderlying(address(this)).mulDivDown(ethBorrowed, ethDebt);
        uint256 res = CDAI.redeemUnderlying(daiToRedeem);
        require(res == 0, "Staking: comp redeem error");

        // Pay debt in maker
        // Send DAI to urn
        JOIN_DAI.join({usr: urn, wad: daiToRedeem});

        // Pay debt. Collateral withdrawn proportional to debt paid
        (uint256 wstEthCollat,) = VAT.urns(ILK, urn);
        uint256 wstEthToRedeem = wstEthCollat.mulDivDown(ethBorrowed, ethDebt);
        MAKER.frob(cdpId, -int256(wstEthToRedeem), -int256(daiToRedeem));

        // Withdraw wstETH from maker
        MAKER.flux({cdp: cdpId, dst: address(this), wad: wstEthToRedeem});
        WSTETH_JOIN.exit(address(this), wstEthToRedeem);

        // Convert from wrapped staked ETH => stETH
        WSTETH.unwrap(wstEthToRedeem);

        // Convert stETH => ETH to pay back flashloan and pay back user
        // Trade stETH for ETH (stETH is at index 1)
        uint256 stEthToTrade = STETH.balanceOf(address(this));
        CURVE.exchange({x: 1, y: 0, dx: stEthToTrade, min_dy: stEthToTrade.mulDivDown(93, 100)});

        // Convert to wETH
        WETH.deposit{value: address(this).balance}();

        // Convert wETH => DAI to pay back flashloan
        if (daiBorrowed > 0) {
            ISwapRouter.ExactOutputSingleParams memory uniParams = ISwapRouter.ExactOutputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(DAI),
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: daiBorrowed,
                amountInMaximum: _daiToEth(daiBorrowed, _getDaiPrice()).mulDivUp(110, 100),
                sqrtPriceLimitX96: 0
            });
            UNI_ROUTER.exactOutputSingle(uniParams);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              REBALANCING
    //////////////////////////////////////////////////////////////*/

    /// @notice Borrow from maker and supply to compound or vice-versa.
    /// @param amountEth Amount of ETH to borrow from compound.
    /// @param amountDai Amount of DAI to borrow from maker.
    function rebalance(uint256 amountEth, uint256 amountDai) external onlyRole(STRATEGIST_ROLE) {
        // ETH price goes up => borrow more DAI from maker and supply to compound
        // ETH price goes down => borrow more ETH from compound and supply to maker
        if (amountEth > 0) {
            // Borrow
            uint256 borrowRes = CETH.borrow(amountEth);
            require(borrowRes == 0, "Staking: borrow failed");

            // Deposit in maker
            uint256 amountWStEth = _ethToSteth();
            MAKER.frob(cdpId, int256(amountWStEth), int256(0));
        }

        if (amountDai > 0) {
            // Borrow DAI from maker
            _borrowDai(0, amountDai);

            // Deposit DAI in compound v2
            CDAI.mint({underlying: amountDai});
        }
    }
    /*//////////////////////////////////////////////////////////////
                           VALUATION
    //////////////////////////////////////////////////////////////*/

    function totalLockedValue() public override returns (uint256) {
        if (MAKER.owns(cdpId) != address(this)) return 0;

        // Maker collateral (ETH), Maker debt (DAI)
        // compound collateral (DAI), compound debt (ETH)
        // TVL = Maker collateral + compound collateral - maker debt - compound debt
        (uint256 makerCollateral, uint256 makerDebt, uint256 compoundCollateral, uint256 compoundDebt) =
            getPositionInfo();

        return WETH.balanceOf(address(this)) + makerCollateral + compoundCollateral - makerDebt - compoundDebt;
    }

    function getPositionInfo()
        public
        returns (uint256 makerCollateral, uint256 makerDebt, uint256 compoundCollateral, uint256 compoundDebt)
    {
        (uint256 wstEthCollat, uint256 rawMakerDebt) = VAT.urns(ILK, urn);

        // Using ETH denomination for everything
        uint256 daiPrice = _getDaiPrice();

        makerCollateral = WSTETH.getStETHByWstETH(wstEthCollat);
        compoundCollateral = _daiToEth(CDAI.balanceOfUnderlying(address(this)), daiPrice);

        makerDebt = _daiToEth(rawMakerDebt, daiPrice);
        compoundDebt = CETH.borrowBalanceCurrent(address(this));
    }

    AggregatorV3Interface public constant WSTETH_ETH_FEED =
        AggregatorV3Interface(0x806b4Ac04501c29769051e42783cF04dCE41440b);


    /*//////////////////////////////////////////////////////////////
                                  LIDO
    //////////////////////////////////////////////////////////////*/

    IWETH public constant WETH = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IWSTETH public constant WSTETH = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    function _getEthToWstEthRatio() internal returns (uint) {
         (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = WSTETH_ETH_FEED.latestRoundData();
        require(price > 0, "LidoLevL2: price <= 0");
        require(answeredInRound >= roundId, "LidoLevL2: stale data");
        require(timestamp != 0, "LidoLevL2: round not done");
        return uint(price);
    }
    function _wstEthToEth(uint amountWstEth) internal returns (uint) {
        return amountWstEth.mulWadDown(_getEthToWstEthRatio());

    }

    function _ethToWstEth(uint amountEth) internal returns (uint) {
        // This is (ETH * 1e18) / price. The price feed gives the ETH/wstETH ratio, and we divide by price to get amount of wstETH.
        // `divWad` is used because both both ETH and the price feed have 18 decimals (the decimals are retained after division).
        return amountEth.divWadDown(_getEthToWstEthRatio());
    }


    /*//////////////////////////////////////////////////////////////
                                 TRADES
    //////////////////////////////////////////////////////////////*/
    ICurvePool public constant CURVE = ICurvePool(0x11C1fBd4b3De66bC0565779b35171a6CF3E71f59);
}
