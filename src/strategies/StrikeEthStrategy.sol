// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICToken} from "src/interfaces/compound/ICToken.sol";
import {IComptroller} from "src/interfaces/compound/IComptroller.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {AffineVault, Strategy} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {IBalancerVault, IFlashLoanRecipient} from "src/interfaces/balancer.sol";
import {SlippageUtils} from "src/libs/SlippageUtils.sol";

contract StrikeEthStrategy is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    /// @notice The wETH address.
    IWETH public constant WETH = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    constructor(AffineVault _vault, ICToken _cToken, address[] memory strategists)
        AccessStrategy(_vault, strategists)
    {
        cToken = _cToken;
    }

    /*//////////////////////////////////////////////////////////////
                              FLASH LOANS
    //////////////////////////////////////////////////////////////*/

    /// @notice The balancer vault. We'll flashloan wETH from here.
    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /// @notice The different reasons for a flashloan.
    enum LoanType {
        invest,
        divest
    }

    error onlyBalancerVault();

    /// @notice Callback called by balancer vault after flashloan is initiated.
    function receiveFlashLoan(
        ERC20[] memory, /* tokens */
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        if (msg.sender != address(BALANCER)) revert onlyBalancerVault();

        uint256 ethBorrowed = amounts[0];

        // Convert wETH to ETH
        WETH.withdraw(ethBorrowed);

        (LoanType loan) = abi.decode(userData, (LoanType));

        if (loan == LoanType.divest) {
            _endPosition(ethBorrowed);
        } else {
            _addToPosition(ethBorrowed);
        }

        // Payback wETH loan
        WETH.safeTransfer(address(BALANCER), ethBorrowed);
    }

    /*//////////////////////////////////////////////////////////////
                         INVESTMENT/DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Add to leveraged position  upon investment from vault.
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

    /// @dev Add to leveraged position. Deposit into compound and borrow to repay balancer loan.
    function _addToPosition(uint256 ethBorrowed) internal {
        // Deposit ETH into compound
        cToken.mint{value: ethBorrowed}();

        // Borrow 70% of the ETH we just deposited
        uint256 amountToBorrow = ethBorrowed.mulDivDown(7, 10);
        uint256 borrowRes = cToken.borrow(amountToBorrow);
        if (borrowRes != 0) revert CompBorrowError(borrowRes);

        // Convert ETH to wETH for balancer repayment
        WETH.deposit{value: amountToBorrow}();
    }

    /// @dev We need this to receive ETH when calling wETH.withdraw()
    receive() external payable {}

    /// @dev Unlock ETH collateral via flashloan, then repay balancer loan with unlocked collateral.
    function _divest(uint256 amount) internal override returns (uint256) {
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _getDivestFlashLoanAmounts(amount);

        uint256 origAssets = WETH.balanceOf(address(this));

        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LoanType.divest)
        });

        // The loan has been paid, any other unlocked collateral belongs to user
        uint256 unlockedWeth = WETH.balanceOf(address(this)) - origAssets;
        WETH.safeTransfer(address(vault), Math.min(unlockedWeth, amount));
        return unlockedWeth;
    }

    /// @dev Calculate the amount of ETH needed to flashloan to divest `wethToDivest` wETH.
    function _getDivestFlashLoanAmounts(uint256 wethToDivest) internal returns (uint256 ethNeeded) {
        // Proportion of tvl == proportion of debt to pay back
        uint256 tvl = totalLockedValue();
        uint256 ethDebt = cToken.borrowBalanceCurrent(address(this));

        ethNeeded = ethDebt.mulDivDown(wethToDivest, tvl);
    }

    function _endPosition(uint256 ethBorrowed) internal {
        // Proportion of collateral to unlock is same as proportion of debt to pay back (ethBorrowed / debt)
        // We need to calculate this number before paying back debt, since the above fraction will change.
        uint256 collateral = cToken.balanceOfUnderlying(address(this));
        uint256 ethToRedeem = collateral.mulDivDown(ethBorrowed, cToken.borrowBalanceCurrent(address(this)));

        // Pay debt in compound
        cToken.repayBorrow{value: ethBorrowed}();

        // Withdraw same proportion of collateral from aave
        uint256 res = cToken.redeemUnderlying(ethToRedeem);
        if (res != 0) revert CompRedeemError(res);

        // Convert ETH to wETH for balancer repayment and payment to user
        WETH.deposit{value: ethToRedeem}();
    }

    /*//////////////////////////////////////////////////////////////
                              REBALANCING
    //////////////////////////////////////////////////////////////*/

    function rebalance(uint256 ethToSupply, uint256 ethToBorrow) external onlyRole(STRATEGIST_ROLE) {
        if (ethToSupply > 0) {
            cToken.mint{value: ethToSupply}();
        }

        if (ethToBorrow > 0) {
            uint256 borrowRes = cToken.borrow(ethToBorrow);
            if (borrowRes != 0) revert CompBorrowError(borrowRes);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VALUATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The tvl function.
    function totalLockedValue() public override returns (uint256) {
        uint256 debt = cToken.borrowBalanceCurrent(address(this));
        uint256 collateral = cToken.balanceOfUnderlying(address(this));

        return collateral - debt;
    }

    /*//////////////////////////////////////////////////////////////
                                  COMPOUND
    //////////////////////////////////////////////////////////////*/

    /// @notice cEther address
    ICToken public immutable cToken;

    /// @notice The COMPTROLLER
    IComptroller public constant COMPTROLLER = IComptroller(0xe2e17b2CBbf48211FA7eB8A875360e5e39bA2602);

    /// @notice The stike governance token.
    ERC20 public constant COMP = ERC20(0x74232704659ef37c08995e386A2E26cc27a8d7B1);

    error CompBorrowError(uint256 errorCode);
    error CompRedeemError(uint256 errorCode);

    /// @notice Uni ROUTER for swapping COMP to `asset`
    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /// @notice The leverage factor of the position multiplied by 100. E.g. 150 would be 1.5x leverage.
    uint256 public leverage = 333; // 3.33x

    /// @notice Set the leverage factor.
    /// @param _leverage The new leverage.
    function setLeverage(uint256 _leverage) external onlyRole(STRATEGIST_ROLE) {
        leverage = _leverage;
    }

    function _claim() internal {
        ICToken[] memory cTokens = new ICToken[](1);
        cTokens[0] = cToken;
        COMPTROLLER.claimComp(address(this), cTokens);
    }

    function claimRewards() external onlyRole(STRATEGIST_ROLE) {
        _claim();
    }

    function claimAndSellRewards(uint256 minAssetsFromReward) external onlyRole(STRATEGIST_ROLE) {
        _claim();

        address[] memory path = new address[](3);
        path[0] = address(COMP);
        path[1] = address(WETH);
        path[2] = address(asset);

        uint256 compBalance = COMP.balanceOf(address(this));
        if (compBalance > 0.01e18) {
            ROUTER.swapExactTokensForTokens({
                amountIn: compBalance,
                amountOutMin: minAssetsFromReward,
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }
    }
}
