// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {IFlashLoanRecipient} from "src/interfaces/balancer/IFlashLoanRecipient.sol";
import {IBalancerVault} from "src/interfaces/balancer/IBalancerVault.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {IWStEth} from "src/interfaces/lido/IWStEth.sol";
import {ICdpManager, IVat, IGemJoin, ICropper} from "src/interfaces/maker.sol";
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
    IWStEth public constant LIDO = IWStEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ICdpManager public constant MAKER = ICdpManager(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    IGemJoin public constant WSTETH_JOIN = IGemJoin(0x10CD5fbe1b404B7E19Ef964B63939907bdaf42E2);
    IGemJoin public constant joinDai = IGemJoin(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    IVat public constant VAT = IVat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    /// @dev cast --to-bytes32 $(cast --from-utf8 "WSTETH-A");
    bytes32 public constant ilk = 0x5753544554482d41000000000000000000000000000000000000000000000000;

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

        // Dai minting
        ERC20(address(LIDO)) .safeApprove(address(WSTETH_JOIN), type(uint256).max);

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
        balancer.flashLoan({recipient: IFlashLoanRecipient(address(this)), tokens: tokens, amounts: amounts, userData: abi.encode(Loan.open)});
    }

    enum Loan {
        open,
        close
    }
  
    function receiveFlashLoan(
        ERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        require(msg.sender == address(balancer), "Staking: only balancer");

        uint256 ethBorrowed = amounts[0];
        console.log("\n\nethBorrowed: %s", ethBorrowed);
        (Loan l) = abi.decode(userData, (Loan));

        if (l == Loan.close) {
            _endPosition(ethBorrowed);
        } else {
            _openPosition(ethBorrowed);
        }
        
        // Payback loan
        console.log("WETH balance before payback: %s", WETH.balanceOf(address(this)));
        WETH.safeTransfer(address(balancer), ethBorrowed);
        // We take slightly more from the user than they want to deposit (for slippage). If there's any left over send back to the user.
        if (l == Loan.open) WETH.safeTransfer(address(vault), WETH.balanceOf(address(this)));
    }

    function _openPosition(uint ethBorrowed) internal {
        // Convert WETH to stEth
        IWETH(address(WETH)).withdraw(ethBorrowed);
        Address.sendValue(payable(address(LIDO)), ethBorrowed);

        uint compoundDebtEth = _openCdp(ERC20(address(LIDO)).balanceOf(address(this)));

        // Convert eth to weth in order to pay back balancer flash loan of weth
        IWETH(address(WETH)).deposit{value: compoundDebtEth}();
        console.log("End eth bal: ", WETH.balanceOf(address(this)));
    }

    uint public cdpId;

    function _openCdp(uint amountWStEth) internal returns (uint compoundDebtEth){
        cdpId = MAKER.open(ilk, address(this));
        address urn = MAKER.urns(cdpId);

        // Lock wsteth in maker
        WSTETH_JOIN.join(urn, amountWStEth);

        // Borrow at 58% collateral ratio. WSTETH is $2.1k.
        uint debt = (amountWStEth * 2126).mulDivDown(58, 100); // TODO: use oracle prices and get 58% in Dai
        MAKER.frob(cdpId, int(amountWStEth), int(debt)); 
        
        // Transfer Dai from cdp to this contract
        MAKER.move({cdp: cdpId, dst: address(this), rad: debt * 1e27});
        VAT.hope(address(joinDai));
        joinDai.exit(address(this), debt);

        console.log("DAI borrowed: ", debt);

        // Deposit Dai in compound v2
        cDAI.mint({underlying: debt});

        // Borrow at 75%
        console.log("Eth bal before borrow: ", WETH.balanceOf(address(this)));
        compoundDebtEth= debt.mulDivDown(75, 100 * 1870); // TODO: Use ETH/DAI oracle
        uint borrowRes = cETH.borrow(compoundDebtEth); // TODO: Use ETH/DAI oracle
        require(borrowRes == 0, "Staking: borrow failed");
    }

     function totalLockedValue() public override returns (uint256) {
        // Maker collateral, Maker debt (dai)
        // compound collateral (dai), compound debt (eth)

        // TVL = Maker collateral + compound collateral - maker debt - compound debt
        // When using cropper, you need to get urn address from cropper instead of cdp manager
        address urn = address(0);

        (uint curveLp, uint daiDebt) = VAT.urns(ilk, urn);

        console.log("CdpId: %s, Curve lp: %s,  Dai debt: %s", cdpId, 0, daiDebt);

        // Using ETH denomination for everything
        uint makerCollateral = 0;
        uint compoundCollateral = cDAI.balanceOfUnderlying(address(this));

        uint ethDebt = cETH.borrowBalanceCurrent(address(this));

        // console.log("makerCollateral: %s, compoundCollateral: %s, daiDebt %s", makerCollateral, compoundCollateral / 1850, daiDebt / 1850);
        console.log("ethDebt: ", ethDebt);
    
        return makerCollateral + (compoundCollateral / 1870) - (daiDebt / 1870) - ethDebt;
     }

     function _divest(uint amount) internal override returns (uint256) {
        uint ethDebt = cETH.borrowBalanceCurrent(address(this));
        uint ethNeeded = ethDebt.mulDivDown(amount, totalLockedValue());

        // Flashloan `ethNeeded` eth from balancer, _endPosition gets called
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ethNeeded;
        balancer.flashLoan({recipient: IFlashLoanRecipient(address(this)), tokens: tokens, amounts: amounts, userData: abi.encode(Loan.close)});

        // Unlocked collateral is equal to my current weth balance
        // Send eth back to user
        uint wethToSend = WETH.balanceOf(address(this));
        WETH.safeTransfer(msg.sender, wethToSend);
        return wethToSend;
     }

       function _endPosition(uint256 ethBorrowed) internal {
        // Pay debt in compound
        uint ethDebt = cETH.borrowBalanceCurrent(address(this));
        IWETH(address(WETH)).withdraw(ethBorrowed);
        console.log("about to repay. ethBorrowed: %s, ethDebt: %s", ethBorrowed, ethDebt);

        cETH.repayBorrow{value: ethBorrowed}();
        uint daiToRedeem = cDAI.balanceOfUnderlying(address(this)).mulDivDown(ethBorrowed, ethDebt);
        uint res = cDAI.redeemUnderlying(daiToRedeem);
        console.log("redeemed");
        require(res == 0, "Staking: comp redeem error");

    
        // Get amount of lp tokens to withdraw from maker
        // (uint totalCurveLp,) = VAT.urns(ilk, CROPPER.proxy(address(this)));
        // uint curveLp = totalCurveLp.mulDivDown(ethBorrowed, ethDebt);

        // Pay debt in maker
        VAT.hope(address(0));
        // CROPPER.frob(ilk, address(this), address(this), address(this), -int(curveLp), -int(DAI.balanceOf(address(this))));

        // Withdraw from maker
        // CROPPER.flux({crop: CROP, src: CROPPER.proxy(address(this)), dst: address(this), wad: curveLp});
        // CROPPER.exit(CROP, address(this), curveLp);
        
        // Convert from wrapped staked eth => stEth => eth => weth
        // TODO: actually convert from stEth => eth => weth
        LIDO.unwrap(0);
        IWETH(address(WETH)).deposit{value: 0}();
    }

    // TODO: remove this and startPosition
    function endPosition(uint _amount) external onlyRole(STRATEGIST_ROLE) {
        _divest(_amount);
    }
}
