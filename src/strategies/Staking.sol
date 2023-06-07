// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {IFlashLoanRecipient} from "src/interfaces/balancer/IFlashLoanRecipient.sol";
import {IBalancerVault} from "src/interfaces/balancer/IBalancerVault.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {ICurvePool} from "src/interfaces/curve.sol";
import {ICdpManager, IVat, IMakerAdapter} from "src/interfaces/maker.sol";

contract StakingExp is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IBalancerVault balancer;
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    // TODO: use IWETH
    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IStEth public constant LIDO = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool public constant CURVE = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    

    /// @dev Aave deposit receipt token.
    ERC20 public immutable aToken;
    /// @dev Aave debt receipt token.
    ERC20 public immutable debtToken;
    IPool public constant AAVE = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ICdpManager public constant MAKER = ICdpManager(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    IMakerAdapter public constant MAKER_ADAPTER = IMakerAdapter(0x82D8bfDB61404C796385f251654F6d7e92092b5D);
    IMakerAdapter public constant joinDai = IMakerAdapter(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    IVat public constant VAT = IVat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    /// @notice The leverage factor of the position in %. e.g. 150 would be 1.5x leverage.
    uint256 public immutable leverage;

    constructor(AffineVault _vault, address[] memory strategists, IBalancerVault _balancer, uint _leverage) AccessStrategy(_vault, strategists) {
        balancer = _balancer;
        leverage = _leverage;

        ERC20(address(LIDO)).safeApprove(address(CURVE), type(uint256).max);
        WETH.safeApprove(address(CURVE), type(uint256).max);
        DAI.approve(address(MAKER_ADAPTER), type(uint256).max);

        aToken = ERC20(AAVE.getReserveData(address(WSTETH)).aTokenAddress);
        debtToken = ERC20(AAVE.getReserveData(address(WETH)).variableDebtTokenAddress);

        WETH.safeApprove(address(ROUTER), type(uint256).max);
        WSTETH.safeApprove(address(ROUTER), type(uint256).max);

        WSTETH.safeApprove(address(AAVE), type(uint256).max);
        aToken.safeApprove(address(AAVE), type(uint256).max);
        WETH.safeApprove(address(AAVE), type(uint256).max);
    }

    uint256 public lastPosSize;
    int256 public lastPosPnl;

    /// @dev Always begin with raw ETH, and 0 WETH
    function startPosition(uint256 size, uint256 slippageBps) external onlyRole(STRATEGIST_ROLE) {
        // Make sure balance is at least 1.005 * the intended deposit size
        uint256 ethNeeded = size + size.mulDivUp(slippageBps * 10, 10_000);
        require(ethNeeded <= address(this).balance, "Staking: insufficient balance");
        // E.g. if we want to get leverage on 1 Eth, we need about 1.005 to account slippage in WETH -> wstETH trade
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = size.mulDivUp(leverage, 100);
        IWETH(address(WETH)).deposit{value: ethNeeded}();
        lastPosSize = ethNeeded;

        balancer.flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, abi.encode(Loan.open, size));
    }

    enum Loan {
        open,
        close
    }

    function endPosition() external onlyRole(STRATEGIST_ROLE) {
        // Take loan for amount of debt from aave
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtToken.balanceOf(address(this));
        balancer.flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, abi.encode(Loan.close, uint256(0)));
    }

    function _endPosition(uint256 amount) internal {
        // Withdraw wstEth from aave

        AAVE.repay({
            asset: address(WETH),
            amount: debtToken.balanceOf(address(this)),
            interestRateMode: 2,
            onBehalfOf: address(this)
        });
        AAVE.withdraw({asset: address(WSTETH), amount: aToken.balanceOf(address(this)), to: address(this)});

        // Swap wstETH to WETH
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WSTETH),
            tokenOut: address(WETH),
            fee: 500,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: WSTETH.balanceOf(address(this)),
            amountOutMinimum: 0, // TODO: slippage protection
            sqrtPriceLimitX96: 0
        });
        ROUTER.exactInputSingle(params);

        // Pay back flash loan using WETH
        WETH.safeTransfer(address(balancer), amount);

        lastPosPnl = int256(WETH.balanceOf(address(this))) - int256(lastPosSize);

        // Unwrap all WETH
        IWETH(address(WETH)).withdraw(WETH.balanceOf(address(this)));
    }

    function receiveFlashLoan(
        ERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        require(msg.sender == address(balancer), "Staking: only balancer");

        ERC20 borrow = tokens[0];
        uint256 amount = amounts[0];

        (Loan loanType, uint256 posSize) = abi.decode(userData, (Loan, uint256));
        if (loanType == Loan.close) {
            return _endPosition(amount);
        }

        // Convert WETH to stEth
        uint want = amount / 2;
        IWETH(address(WETH)).withdraw(want);
        LIDO.submit{value: want}(address(this));

        // Deposit in curve
        uint256[2] memory depositAmounts = [uint256(0), 0];
        depositAmounts[1] = amount - want;
        uint amountLp = CURVE.add_liquidity(depositAmounts, 0); // TODO: slippage

        // Borrow on oasis
        _openCdp(amountLp);
    
        // Payback loan
        borrow.safeTransfer(address(vault), amount);
    }

    function _openCdp(uint amountLp) internal  {
        // cast --to-bytes32 $(cast --from-utf8 "CRVV1ETHSTETH-A")
        bytes32 ilk = 0x435256563145544853544554482d410000000000000000000000000000000000;
        uint cdpId = MAKER.open(ilk, address(this));
        address urn = MAKER.urns(cdpId);

        // Lock eth in maker
        MAKER_ADAPTER.join(urn, address(this), amountLp);
        // Borrow at 58% collateral ratio
        uint debt = amountLp.mulDivDown(1900 * 58, 100);
        MAKER.frob(cdpId, int(amountLp), int(debt)); // TODO: use oracle prices and get 58% in Dai
        
        // Transfer Dai from cdp to this contract
        MAKER.move(cdpId, address(this), debt * 1e27); // need 45 decimals instead of 18
        VAT.hope(address(joinDai));
        joinDai.exit(address(this), debt);
    }
}
