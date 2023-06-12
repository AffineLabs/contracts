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
import {ICdpManager, IVat, IMakerAdapter, ICropper} from "src/interfaces/maker.sol";
import {ICToken} from "src/interfaces/compound/ICToken.sol";
import {IComptroller} from "src/interfaces/compound/IComptroller.sol";


import "forge-std/console.sol";

contract StakingExp is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IBalancerVault balancer;
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    // TODO: use IWETH
    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStEth public constant LIDO = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool public constant CURVE = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    

    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ICdpManager public constant MAKER = ICdpManager(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    ICropper public constant CROPPER = ICropper(0x8377CD01a5834a6EaD3b7efb482f678f2092b77e);
    address public constant CROP = 0x82D8bfDB61404C796385f251654F6d7e92092b5D;
    IMakerAdapter public constant joinDai = IMakerAdapter(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    IVat public constant VAT = IVat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    /// @dev cast --to-bytes32 $(cast --from-utf8 "CRVV1ETHSTETH-A");
    bytes32 public ilk = 0x435256563145544853544554482d410000000000000000000000000000000000;

    /// @notice cETH
    ICToken public constant cETH = ICToken(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    /// @notice cDAI
    ICToken public constant cDAI = ICToken(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    /// @notice The leverage factor of the position in %. e.g. 150 would be 1.5x leverage.
    uint256 public immutable leverage;

    constructor(AffineVault _vault, address[] memory strategists, IBalancerVault _balancer, uint _leverage) AccessStrategy(_vault, strategists) {
        balancer = _balancer;
        leverage = _leverage;


        // Lido
        ERC20(address(LIDO)).safeApprove(address(CURVE), type(uint256).max);

        // Curve lp and dai minting
        WETH.safeApprove(address(CURVE), type(uint256).max);
        ERC20(address(LIDO)).safeApprove(address(CURVE), type(uint256).max);
        ERC20 lpToken = ERC20(CURVE.lp_token());
        lpToken.safeApprove(address(CROPPER), type(uint256).max);

        DAI.safeApprove(address(CROPPER), type(uint).max); // TODO: check if this is needed

        // Compound deposits/borrow
        DAI.safeApprove(address(cDAI), type(uint256).max);
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cDAI);

        uint256[] memory results = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B).enterMarkets(cTokens);
        require(results[0] == 0, "Staking: failed to enter market");

    }


    /// @notice Start a position with `size` principal, taking up to`maxPrincipal` from the user. 
    function startPosition(uint256 size, uint256 maxPrincipal) external onlyRole(STRATEGIST_ROLE) {
 
        require(maxPrincipal >= size, "Staking: max > size");
        WETH.safeTransferFrom(msg.sender, address(this), maxPrincipal);
        

        // Prepare flash loan
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = size.mulDivUp(leverage, 100);

        balancer.flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, abi.encode(Loan.open, size, msg.sender));
    }

    enum Loan {
        open,
        close
    }

    function endPosition() external onlyRole(STRATEGIST_ROLE) {
    }

    function _endPosition(uint256 amount) internal {
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
        console.log("Borrowed amount: ", amount);

        (Loan loanType, uint256 posSize, address user) = abi.decode(userData, (Loan, uint256, address));
        if (loanType == Loan.close) {
            return _endPosition(amount);
        }

        // Convert WETH to stEth
        uint want = amount / 2;
        IWETH(address(WETH)).withdraw(amount);
        LIDO.submit{value: want}(address(this));

        // Deposit in curve
        uint ethDeposit = amount - want;
        uint256[2] memory depositAmounts = [ethDeposit, ERC20(address(LIDO)).balanceOf(address(this))];
        uint amountLp = CURVE.add_liquidity{value: ethDeposit}(depositAmounts, 0); // TODO: slippage

        // Open cdp
        _openCdp(amountLp);
    
        // Payback loan
        borrow.safeTransfer(address(balancer), amount);

        WETH.safeTransfer(user, WETH.balanceOf(address(this))); // Send leftover weth back to user
    }

    uint public cdpId;
    // uint public urn;

    function _openCdp(uint amountLp) internal {
        cdpId = MAKER.open(ilk, address(this));

        // Lock eth in maker
        CROPPER.join(CROP, address(this), amountLp);
        // Roughly 589_444 eth in pool and 539_973 lp tokens
        // Borrow at 58% collateral ratio
        uint amountEth = amountLp.mulDivDown(11, 10);
        uint debt = amountEth.mulDivDown(58, 100) * 1850; // TODO: use oracle prices and get 58% in Dai
        CROPPER.frob(ilk, address(this), address(this), address(this), int(amountLp), int(debt)); 
        
        // Transfer Dai from cdp to this contract
        VAT.hope(address(joinDai));
        joinDai.exit(address(this), debt);

        console.log("DAI borrowed: ", debt);

        // Deposit Dai in compound v2
        cDAI.mint({underlying: debt});

        // Borrow at 75%
        console.log("Eth bal before borrow: ", WETH.balanceOf(address(this)));
        uint amountEthToBorrow = debt.mulDivDown(75, 100 * 1870); // TODO: Use ETH/DAI oracle
        uint borrowRes = cETH.borrow(amountEthToBorrow); // TODO: Use ETH/DAI oracle
        require(borrowRes == 0, "Staking: borrow failed");

        // Convert eth to weth
        IWETH(address(WETH)).deposit{value: amountEthToBorrow}();

        // Pay back loan
        console.log("End eth bal: ", WETH.balanceOf(address(this)));
    }

     function totalLockedValue() external override returns (uint256) {
        // Maker collateral, Maker debt (dai)
        // compound collateral (dai), compound debt (eth)

        // TVL = Maker collateral + compound collateral - maker debt - compound debt
        // When using cropper, you need to get urn address from cropper instead of cdp manager
        address urn = CROPPER.proxy(address(this));

        (uint curveLp, uint daiDebt) = VAT.urns(ilk, urn);

        console.log("CdpId: %s,  Curve lp: %s,  Dai debt: %s", cdpId, curveLp, daiDebt);

        // Using ETH denomination for everything

        uint makerCollateral = CURVE.calc_withdraw_one_coin(curveLp, 0);

        uint compoundCollateral = cDAI.balanceOfUnderlying(address(this));

        uint ethDebt = cETH.borrowBalanceCurrent(address(this));

        console.log("makerCollateral: %s, compoundCollateral: %s, daiDebt %s", makerCollateral, compoundCollateral / 1850, daiDebt / 1850);
        console.log("ethDebt: ", ethDebt);
    
        return makerCollateral + (compoundCollateral / 1870) - (daiDebt / 1870) - ethDebt;
     }
}
