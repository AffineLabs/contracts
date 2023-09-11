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

import "forge-std/console.sol";

contract LidoLevL2 is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;
    using SafeTransferLib for IWSTETH;
    using FixedPointMathLib for uint256;

    IPool public constant AAVE = IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    ERC20 public immutable debtToken;
    ERC20 public immutable aToken;

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
        WETH.safeApprove(address(AAVE), type(uint256).max);

        aToken  = ERC20(AAVE.getReserveData(address(WSTETH)).aTokenAddress);
        debtToken = ERC20(AAVE.getReserveData(address(WETH)).variableDebtTokenAddress);
        AAVE.setUserEMode(1); // 1 = enabled

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
        ERC20[] memory /* tokens */,
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        require(msg.sender == address(BALANCER), "Staking: only balancer");

        uint256 ethBorrowed = amounts[0];
        (LoanType loan) = abi.decode(userData, (LoanType));

        if (loan == LoanType.divest) {
            _endPosition(ethBorrowed);
        } else {
            _addToPosition(ethBorrowed);
        }

        // Payback wETH loan
        console.log("balance: ", WETH.balanceOf(address(this)));
        WETH.safeTransfer(address(BALANCER), ethBorrowed);
    }

    /*//////////////////////////////////////////////////////////////
                         INVESTMENT/DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice The leverage factor of the position in %. e.g. 150 would be 1.5x leverage.
    uint256 public immutable leverage;

    function _afterInvest(uint256 amount) internal override {
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount.mulDivUp(leverage, 100);
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LoanType.invest)
        });
    }   

    function _addToPosition(uint256 ethBorrowed) internal {
        // Trade ETHto wstETH
        uint expectedWstETh = _ethToWstEth(ethBorrowed);
        // TODO: allow custom slippage params to be set
        uint wstEth = CURVE.exchange({x: uint(0), y: 1, dx: ethBorrowed, min_dy: expectedWstETh.mulDivDown(93, 100)});

        // Deposit wstETH in AAVE
        asset.safeApprove(address(AAVE), type(uint256).max);
        AAVE.deposit(address(WSTETH), wstEth, address(this), 0);

        // Borrow 90% of wstETH value in ETH using e-mode
        uint ethToBorrow =  _wstEthToEth(wstEth).mulDivDown(8999, 10_000);
        AAVE.borrow(address(WETH), ethToBorrow, 2, 0, address(this));
    }

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    function _divest(uint256 amount) internal override returns (uint256) {
        uint256 ethNeeded = _getDivestFlashLoanAmounts(amount);

        // Flashloan `ethNeeded` ETH from balancer, _endPosition gets called
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ethNeeded;

        uint origAssets = WETH.balanceOf(address(this));
   
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LoanType.divest)
        });


        uint unlockedWeth = WETH.balanceOf(address(this));
        // The loan has been paid, any other unlocked collateral belongs to user
        WETH.safeTransfer(address(vault), unlockedWeth);
        return unlockedWeth;
    }

    function _getDivestFlashLoanAmounts(uint256 wethToDivest) internal view  returns (uint256 ethNeeded) {
        // Proportion of tvl == proportion of debt to pay back
        uint256 tvl = totalLockedValue();
        uint ethDebt = debtToken.balanceOf(address(this));

        ethNeeded = ethDebt.mulDivDown(wethToDivest, tvl);
    }

    function _endPosition(uint256 ethBorrowed) internal {
        // Pay debt in aave
        AAVE.repay(address(WETH), ethBorrowed, 2, address(this));

        // Withdraw same proportion of collateral from aave
        uint wstEthToRedeem = aToken.balanceOf(address(this)).mulDivDown(ethBorrowed, debtToken.balanceOf(address(this)));
        AAVE.withdraw(address(WSTETH), wstEthToRedeem, address(this));

        // Convert wstETH => wETH to prepare flashloan repayment
        // TODO: custom slippage params
        CURVE.exchange({x: uint(1), y: 0, dx: wstEthToRedeem, min_dy: _wstEthToEth(wstEthToRedeem).mulDivDown(93, 100)});
    }

 
    /*//////////////////////////////////////////////////////////////
                           VALUATION
    //////////////////////////////////////////////////////////////*/

    function totalLockedValue() public view override returns (uint256) {
        uint aaveDebt = debtToken.balanceOf(address(this));
        uint aaveCollateral = _wstEthToEth(aToken.balanceOf(address(this)));

        return aaveCollateral - aaveDebt;
    }

    AggregatorV3Interface public constant WSTETH_ETH_FEED =
        AggregatorV3Interface(0x806b4Ac04501c29769051e42783cF04dCE41440b);


    /*//////////////////////////////////////////////////////////////
                                  STAKED ETHER
    //////////////////////////////////////////////////////////////*/

    IWETH public constant WETH = IWETH(payable(0x4200000000000000000000000000000000000006));
    IWSTETH public constant WSTETH = IWSTETH(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);

    function _getEthToWstEthRatio() internal view returns (uint) {
         (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = WSTETH_ETH_FEED.latestRoundData();
        require(price > 0, "LidoLevL2: price <= 0");
        require(answeredInRound >= roundId, "LidoLevL2: stale data");
        require(timestamp != 0, "LidoLevL2: round not done");
        return uint(price);
    }
    function _wstEthToEth(uint amountWstEth) internal view returns (uint) {
        return amountWstEth.mulWadDown(_getEthToWstEthRatio());

    }

    function _ethToWstEth(uint amountEth) internal view returns (uint) {
        // This is (ETH * 1e18) / price. The price feed gives the ETH/wstETH ratio, and we divide by price to get amount of wstETH.
        // `divWad` is used because both both ETH and the price feed have 18 decimals (the decimals are retained after division).
        return amountEth.divWadDown(_getEthToWstEthRatio());
    }


    /*//////////////////////////////////////////////////////////////
                                 TRADES
    //////////////////////////////////////////////////////////////*/
    ICurvePool public constant CURVE = ICurvePool(0x11C1fBd4b3De66bC0565779b35171a6CF3E71f59);
}
