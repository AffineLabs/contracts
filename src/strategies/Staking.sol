// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {IFlashLoanRecipient} from "src/interfaces/balancer/IFlashLoanRecipient.sol";
import {IBalancerVault} from "src/interfaces/balancer/IBalancerVault.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

contract StakingExp is IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IBalancerVault vault;
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant WSTETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704); // actually coinbase Eth
    IPool public constant AAVE = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    constructor(IBalancerVault _vault) {
        vault = _vault;
        WETH.safeApprove(address(ROUTER), type(uint256).max);
        WSTETH.safeApprove(address(ROUTER), type(uint256).max);

        WSTETH.safeApprove(address(AAVE), type(uint256).max);
    }

    function startPosition(uint256 size, uint256 slippageBps) external {
        // Make sure balance is at least 1.005 * the intended deposit size
        uint256 ethNeeded = size + size.mulDivUp(slippageBps * 10, 10_000);
        require(ethNeeded <= address(this).balance, "Staking: insufficient balance");
        // E.g. if we want to get leverage on 1 Eth, we need about 1.005 to account slippage in WETH -> wstETH trade
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = size * 10;
        IWETH(address(WETH)).deposit{value: size}();

        vault.flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, abi.encodePacked(size));
    }

    function receiveFlashLoan(
        ERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory, /*feeAmounts */
        bytes memory userData
    ) external override {
        ERC20 asset = tokens[0];
        uint256 amount = amounts[0];

        // WETH to wstETH (via trade)
        // Uniswap pool is pretty big: https://info.uniswap.org/#/pools/0x840deeef2f115cf50da625f7368c24af6fe74410
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(WSTETH),
            fee: 500,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        ROUTER.exactInputSingle(params);

        // Supply wstEth on AAVE
        AAVE.supply({
            asset: address(WSTETH),
            amount: WSTETH.balanceOf(address(this)),
            onBehalfOf: address(this),
            referralCode: 0
        });

        // Borrow Eth. TODO: consider converting WSTETH to ETH using oracle prices
        // TODO: make sure collat ratio is safe
        AAVE.setUserEMode(1); // Allow up to 90% borrow
        uint256 posSize = abi.decode(userData, (uint256));
        AAVE.borrow({
            asset: address(WETH),
            amount: amount - posSize,
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: address(this)
        });

        // Payback loan
        asset.safeTransfer(address(vault), amount);
    }
}
