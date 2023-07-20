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


contract StakingExp is AccessStrategy, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    // TODO: use IWETH
    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IWStEth public constant LIDO = IWStEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool public constant CURVE = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ICdpManager public constant MAKER = ICdpManager(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    IGemJoin public constant WSTETH_JOIN = IGemJoin(0x10CD5fbe1b404B7E19Ef964B63939907bdaf42E2);
    IGemJoin public constant JOIN_DAI = IGemJoin(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    IVat public constant VAT = IVat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    /// @dev cast --to-bytes32 $(cast --from-utf8 "WSTETH-A");
    bytes32 public constant ILK = 0x5753544554482d41000000000000000000000000000000000000000000000000;

    /// @notice cETH
    ICToken public constant CETH = ICToken(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    /// @notice cDAI
    ICToken public constant CDAI = ICToken(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

    AggregatorV3Interface public constant ETH_DAI_FEED = AggregatorV3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4);

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
        DAI.approve(address(JOIN_DAI), type(uint256).max);

        // Compound deposits/borrow
        DAI.safeApprove(address(CDAI), type(uint256).max);
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(CDAI);

        uint256[] memory results = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B).enterMarkets(cTokens);
        require(results[0] == 0, "Staking: failed to enter market");

        // Trade stEth for Eth
        STETH.safeApprove(address(CURVE), type(uint).max);
        // Trade weth for Dai
        WETH.safeApprove(address(ROUTER), type(uint).max);
    }

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
        uint daiBorrowed;
        (LoanType loan) = abi.decode(userData, (LoanType));

        if (loan == LoanType.divest) {
            // We only flashloan dai in certain cases during divestment
            if (tokens.length == 2) {
                daiBorrowed = amounts[0];
                ethBorrowed = amounts[1];
            } else {
                ethBorrowed = amounts[0];
            }
            _endPosition(ethBorrowed, daiBorrowed);
        } else  if (loan == LoanType.invest){
            ethBorrowed = amounts[0];
            _addToPosition(ethBorrowed);
        }
        
        // Payback Weth loan
        WETH.safeTransfer(address(BALANCER), ethBorrowed);

        // Repay Dai loan
        if (daiBorrowed > 0) DAI.safeTransfer(address(BALANCER), daiBorrowed);
    }

    uint public cdpId;

    function openPosition(uint size) external onlyRole(STRATEGIST_ROLE) {
        require(cdpId == 0, "Staking: position open");
        cdpId = MAKER.open(ILK, address(this));

        _investFlashLoan(size);
    }

    function addToPosition(uint size) external onlyRole(STRATEGIST_ROLE) {
        _investFlashLoan(size);
    }

    function _investFlashLoan(uint size) internal {
          ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = size.mulDivUp(leverage, 100);
        BALANCER.flashLoan({recipient: IFlashLoanRecipient(address(this)), tokens: tokens, amounts: amounts, userData: abi.encode(LoanType.invest)});
    }

    function _addToPosition(uint ethBorrowed) internal {
        // Convert all eth in vault to wsteth
        IWETH(address(WETH)).withdraw(ethBorrowed);
        Address.sendValue(payable(address(LIDO)), ethBorrowed);
        uint amountWStEth = ERC20(address(LIDO)).balanceOf(address(this));

        // Lock wsteth in maker
        address urn = MAKER.urns(cdpId);
        WSTETH_JOIN.join(urn, amountWStEth);

        // Borrow at 58% collateral ratio
        uint daiPrice = _getDaiPrice();
        uint debt = _ethToDai(LIDO.getStETHByWstETH(amountWStEth), daiPrice).mulDivDown(58, 100);
        MAKER.frob(cdpId, int(amountWStEth), int(debt)); 
        
        // Transfer Dai from cdp to this contract
        MAKER.move({cdp: cdpId, dst: address(this), rad: debt * 1e27});
        VAT.hope(address(JOIN_DAI));
        JOIN_DAI.exit(address(this), debt);

        // Deposit Dai in compound v2
        CDAI.mint({underlying: debt});

        // Borrow at 75%
        uint compoundDebtEth = _daiToEth(debt, daiPrice).mulDivDown(75, 100); 
        uint borrowRes = CETH.borrow(compoundDebtEth);
        require(borrowRes == 0, "Staking: borrow failed");

        // Convert eth to weth in order to pay back balancer flash loan of weth
        IWETH(address(WETH)).deposit{value: compoundDebtEth}();
    }

     function totalLockedValue() public override returns (uint256) {
        // Maker collateral, Maker debt (dai)
        // compound collateral (dai), compound debt (eth)
        // TVL = Maker collateral + compound collateral - maker debt - compound debt
        address urn = MAKER.urns(cdpId);
        (uint wstEthCollat, uint rawMakerDebt) = VAT.urns(ILK, urn);

        // Using ETH denomination for everything
        uint daiPrice = _getDaiPrice();

        uint makerCollateral = LIDO.getStETHByWstETH(wstEthCollat);
        uint compoundCollateral = _daiToEth(CDAI.balanceOfUnderlying(address(this)), daiPrice);

        uint makerDebt = _daiToEth(rawMakerDebt, daiPrice);
        uint compoundDebt = CETH.borrowBalanceCurrent(address(this));

        return makerCollateral + compoundCollateral - makerDebt - compoundDebt;
     }


    function _getDaiPrice() internal view returns (uint) {
        (uint80 roundId, int256 price,, uint256 timestamp, uint80 answeredInRound) = ETH_DAI_FEED.latestRoundData();
        require(price > 0, "Staking: price <= 0");
        require(answeredInRound >= roundId, "Staking: stale data");
        require(timestamp != 0, "staking: round not done");
        return uint(price);
    }

     function _ethToDai(uint amountEth, uint price) internal pure returns (uint) {
        // This is (eth * 1e18) / price. The price feed gives the eth/dai ratio, and we divide by price to get amount of dai.
        // `divWad` is used because both both eth and the price feed have 18 decimals (the decimals are retained after division).
        return amountEth.divWadDown(price);
     }

     function _daiToEth(uint amountDai, uint price) internal pure returns (uint) {
        return amountDai.mulWadDown(price);
     }

     function _divest(uint amount) internal override returns (uint256) {
        uint tvl = totalLockedValue();
        uint ethDebt = CETH.borrowBalanceCurrent(address(this));
        uint ethNeeded = ethDebt.mulDivDown(amount, tvl);

        uint compDaiToRedeem = (CDAI.balanceOfUnderlying(address(this)).mulDivDown(amount, tvl));
        (, uint makerDai)  = VAT.urns(ILK, MAKER.urns(cdpId));
        uint makerDaiToPay = makerDai.mulDivDown(amount, tvl);

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

        BALANCER.flashLoan({recipient: IFlashLoanRecipient(address(this)), tokens: tokens, amounts: amounts, userData: abi.encode(LoanType.divest)});

        // Unlocked collateral is equal to my current weth balance
        // Send eth back to user
        uint wethToSend = WETH.balanceOf(address(this));
        WETH.safeTransfer(msg.sender, wethToSend);
        return wethToSend;
     }

       function _endPosition(uint256 ethBorrowed, uint daiBorrowed) internal {
        // Pay debt in compound
        uint ethDebt = CETH.borrowBalanceCurrent(address(this));
        IWETH(address(WETH)).withdraw(ethBorrowed);

        CETH.repayBorrow{value: ethBorrowed}();
        uint daiToRedeem = CDAI.balanceOfUnderlying(address(this)).mulDivDown(ethBorrowed, ethDebt);
        uint res = CDAI.redeemUnderlying(daiToRedeem);
        require(res == 0, "Staking: comp redeem error");

        // Pay debt in maker

        // Send the dai to urn
        address urn = MAKER.urns(cdpId);
        JOIN_DAI.join({usr: urn, wad: daiToRedeem});

        // Pay debt. Collateral withdrawn proportional to debt paid
        (uint wstEthCollat,)  = VAT.urns(ILK, urn);
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
             ISwapRouter.ExactInputSingleParams memory uniParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(DAI),
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _daiToEth(daiBorrowed, _getDaiPrice()).mulDivUp(110, 100),
                amountOutMinimum: daiBorrowed,
                sqrtPriceLimitX96: 0
            });
            ROUTER.exactInputSingle(uniParams);
        }  
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
            uint borrowRes = CETH.borrow(amountEth);
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
            CDAI.mint({underlying: amountDai});
        }
    }
}
