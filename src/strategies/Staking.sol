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
import {ICurvePool} from "src/interfaces/curve/ICurvePool.sol";
import {ICdpManager, IVat, IGemJoin, ICropper} from "src/interfaces/maker.sol";
import {ICToken} from "src/interfaces/compound/ICToken.sol";
import {IComptroller} from "src/interfaces/compound/IComptroller.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

import "forge-std/console.sol";

contract StakingExp is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IBalancerVault public constant balancer = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    // TODO: use IWETH
    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IWStEth public constant LIDO = IWStEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool public constant CURVE = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

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


    AggregatorV3Interface public constant ethDaiFeed = AggregatorV3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4);

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    /// @notice The leverage factor of the position in %. e.g. 150 would be 1.5x leverage.
    uint256 public immutable leverage;

    constructor(uint _leverage, AffineVault _vault, address[] memory strategists ) AccessStrategy(_vault, strategists) {
        leverage = _leverage;

        // Dai minting
        // Send wsteth to join contract
        ERC20(address(LIDO)).safeApprove(address(WSTETH_JOIN), type(uint256).max);
       

        // Dai burning / debt payment
        // Allow Dai join to take Dai from this contract
        DAI.approve(address(joinDai), type(uint256).max);

        // Compound deposits/borrow
        DAI.safeApprove(address(cDAI), type(uint256).max);
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cDAI);

        uint256[] memory results = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B).enterMarkets(cTokens);
        require(results[0] == 0, "Staking: failed to enter market");

        // Trade stEth for Eth
        STETH.safeApprove(address(CURVE), type(uint).max);

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

        uint256 ethBorrowed;
        uint daiBorrowed;
        (Loan l) = abi.decode(userData, (Loan));

        if (l == Loan.close) {
            // We only flashloan dai in certain cases during divestment
            if (tokens.length == 2) {
                daiBorrowed = amounts[0];
                ethBorrowed = amounts[1];
            } else {
                ethBorrowed = amounts[0];
            }
            _endPosition(ethBorrowed, daiBorrowed);
        } else {
            ethBorrowed = amounts[0];
            _openPosition(ethBorrowed);
        }
        
        // Payback loan
        WETH.safeTransfer(address(balancer), ethBorrowed);
        // We take slightly more from the user than they want to deposit (for slippage). If there's any left over send back to the user.
        if (l == Loan.open) WETH.safeTransfer(address(vault), WETH.balanceOf(address(this)));

        // Repay Dai loan
        if (daiBorrowed > 0) DAI.safeTransfer(address(balancer), daiBorrowed);
    }
 
    function _openPosition(uint ethBorrowed) internal {
        // Convert WETH to stEth
        IWETH(address(WETH)).withdraw(ethBorrowed);
        Address.sendValue(payable(address(LIDO)), ethBorrowed);

        uint compoundDebtEth = _openCdp(ERC20(address(LIDO)).balanceOf(address(this)));

        // Convert eth to weth in order to pay back balancer flash loan of weth
        IWETH(address(WETH)).deposit{value: compoundDebtEth}();
    }

    uint public cdpId;

    function _openCdp(uint amountWStEth) internal returns (uint compoundDebtEth){
        cdpId = MAKER.open(ilk, address(this));
        address urn = MAKER.urns(cdpId);

        // Lock wsteth in maker
        WSTETH_JOIN.join(urn, amountWStEth);

        // Borrow at 58% collateral ratio
        uint daiPrice = _getDaiPrice();
        uint debt = _ethToDai(LIDO.getStETHByWstETH(amountWStEth), daiPrice).mulDivDown(58, 100);
        MAKER.frob(cdpId, int(amountWStEth), int(debt)); 
        
        // Transfer Dai from cdp to this contract
        MAKER.move({cdp: cdpId, dst: address(this), rad: debt * 1e27});
        VAT.hope(address(joinDai));
        joinDai.exit(address(this), debt);

        // Deposit Dai in compound v2
        cDAI.mint({underlying: debt});

        // Borrow at 75%
        compoundDebtEth= _daiToEth(debt, daiPrice).mulDivDown(75, 100); 
        uint borrowRes = cETH.borrow(compoundDebtEth);
        require(borrowRes == 0, "Staking: borrow failed");
    }

     function totalLockedValue() public override returns (uint256) {
        // Maker collateral, Maker debt (dai)
        // compound collateral (dai), compound debt (eth)
        // TVL = Maker collateral + compound collateral - maker debt - compound debt
        address urn = MAKER.urns(cdpId);
        (uint wstEthCollat, uint rawMakerDebt) = VAT.urns(ilk, urn);

        // Using ETH denomination for everything
        uint daiPrice = _getDaiPrice();

        uint makerCollateral = LIDO.getStETHByWstETH(wstEthCollat);
        uint compoundCollateral = _daiToEth(cDAI.balanceOfUnderlying(address(this)), daiPrice);

        uint makerDebt = _daiToEth(rawMakerDebt, daiPrice);
        uint compoundDebt = cETH.borrowBalanceCurrent(address(this));

        return makerCollateral + compoundCollateral - makerDebt - compoundDebt;
     }


    function _getDaiPrice() internal returns (uint) {
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = ethDaiFeed.latestRoundData();
        require(price > 0, "Staking: price <= 0");
        require(answeredInRound >= roundId, "Staking: stale data");
        require(timestamp != 0, "staking: round not done");
        return uint(price);
    }

     function _ethToDai(uint amountEth, uint price) internal returns (uint) {
        // This is (eth * 1e18) / price. The price feed gives the eth/dai ratio, and we divide by price to get amount of dai.
        // `divWad` is used because both both eth and the price feed have 18 decimals (the decimals are retained after division).
        return amountEth.divWadDown(price);
     }

     function _daiToEth(uint amountDai, uint price) internal returns (uint) {
        return amountDai.mulWadDown(price);
     }

     function _divest(uint amount) internal override returns (uint256) {
        uint tvl = totalLockedValue();
        uint ethDebt = cETH.borrowBalanceCurrent(address(this));
        uint ethNeeded = ethDebt.mulDivDown(amount, tvl);


        uint compDaiToRedeem = (cDAI.balanceOfUnderlying(address(this)).mulDivDown(amount, tvl));
        (, uint makerDai)  = VAT.urns(ilk, MAKER.urns(cdpId));
        uint makerDaiToPay = makerDai.mulDivDown(amount, tvl);

        console.log("compDaiToRedeem: ", compDaiToRedeem);
        console.log("makerDaiToPay: ", makerDaiToPay);

        // Maker debt and comp collateral may diverge over time. Flashloan DAI if need to pay same percentage 
        // of maker debt as we pay of compound debt
        // stEth will be traded to DAI to pay back this flashloan, so we need to set a min amount to make sure the trade succeeds
        uint daiNeeded;
        if (makerDaiToPay > compDaiToRedeem && makerDaiToPay - compDaiToRedeem > 0.01e18) {
            daiNeeded = makerDaiToPay - compDaiToRedeem;
        }

        // Flashloan `ethNeeded` eth from balancer, _endPosition gets called
        // Note that balancer actually token addresses to be sorted, so dai must come before weth
        uint arrSize = daiNeeded > 0 ? 2 : 1;
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
        console.log("daiNeeded", daiNeeded);

        balancer.flashLoan({recipient: IFlashLoanRecipient(address(this)), tokens: tokens, amounts: amounts, userData: abi.encode(Loan.close)});

        // Unlocked collateral is equal to my current weth balance
        // Send eth back to user
        uint wethToSend = WETH.balanceOf(address(this));
        WETH.safeTransfer(msg.sender, wethToSend);
        return wethToSend;
     }

       function _endPosition(uint256 ethBorrowed, uint daiBorrowed) internal {
        // Pay debt in compound
        uint ethDebt = cETH.borrowBalanceCurrent(address(this));
        IWETH(address(WETH)).withdraw(ethBorrowed);

        cETH.repayBorrow{value: ethBorrowed}();
        uint daiToRedeem = cDAI.balanceOfUnderlying(address(this)).mulDivDown(ethBorrowed, ethDebt);
        uint res = cDAI.redeemUnderlying(daiToRedeem);
        require(res == 0, "Staking: comp redeem error");

        // Pay debt in maker

        // Send the dai to urn
        address urn = MAKER.urns(cdpId);
        joinDai.join({usr: urn, wad: daiToRedeem});

        // Pay debt. Collateral withdrawn proportional to debt paid
        (uint wstEthCollat,)  = VAT.urns(ilk, urn);
        uint wstEthToRedeem = wstEthCollat.mulDivDown(ethBorrowed, ethDebt);
        MAKER.frob(cdpId, -int(wstEthToRedeem), -int(daiToRedeem));

        // Withdraw wstEth from maker
        MAKER.flux({cdp: cdpId, dst: address(this), wad: wstEthToRedeem});
        WSTETH_JOIN.exit(address(this), wstEthToRedeem);

        // Convert from wrapped staked eth => stEth 
        LIDO.unwrap(wstEthToRedeem);


        // Convert stEth => eth to pay back flashloan and pay back user
        // Trade on stEth for ETH (steth is at index 1)
        uint stEthToTrade = STETH.balanceOf(address(this));
        CURVE.exchange({x: 1, y: 0 , dx: stEthToTrade, min_dy: stEthToTrade.mulDivDown(93, 100)});

         // Convert to weth
        IWETH(address(WETH)).deposit{value: address(this).balance}();

        // Convert weth => dai to pay back flashloan
        if (daiBorrowed > 0) {
             ISwapRouter.ExactInputSingleParams memory paramsCrv = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(DAI),
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _daiToEth(daiBorrowed, _getDaiPrice()).mulDivUp(110, 100),
                amountOutMinimum: daiBorrowed,
                sqrtPriceLimitX96: 0
            });
        }
        console.log("balance of dai after trade: ", DAI.balanceOf(address(this)));
       
    }

    // TODO: remove this and startPosition
    function endPosition(uint _amount) external onlyRole(STRATEGIST_ROLE) {
        _divest(_amount);
    }


    /// @notice Borrow from maker and supply to compound or vice-versa.
    /// @param amountEth Amount of eth to borrow from compound.
    /// @param amountDai Amount of dai to borrow from maker.
    function rebalance (uint amountEth, uint amountDai) external onlyRole(STRATEGIST_ROLE) {
        // Eth price goes up => borrow more dai from maker and supply to compound
        // Eth price goes down => borrow more eth from compound and supply to maker
        if (amountEth > 0) {
            // borrow
            uint borrowRes = cETH.borrow(amountEth);
            require(borrowRes == 0, "Staking: borrow failed");

            // convert eth to wstEth
            Address.sendValue(payable(address(LIDO)), address(this).balance);


            // deposit in maker
            uint amountWStEth = ERC20(address(LIDO)).balanceOf(address(this));
            MAKER.frob(cdpId, int(amountWStEth), int(0)); 
        }

        if (amountDai > 0) {
            // Borrow dai from maker
            MAKER.frob(cdpId, int(0), int(amountDai));

            // Deposit Dai in compound v2
            cDAI.mint({underlying: amountDai});
        }
    }
}
