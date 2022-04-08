// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseStrategy } from "../BaseStrategy.sol";
import { IConversionPool } from "../interfaces/anchor/IConversionPool.sol";
import { IExchangeRateFeeder } from "../interfaces/anchor/IExchangeRateFeeder.sol";

import { BaseVault } from "../BaseVault.sol";

// https://docs.anchorprotocol.com/ethanchor/ethanchor-contracts
contract L1AnchorStrategy is BaseStrategy {
    using SafeTransferLib for ERC20;

    // aUSDC.
    ERC20 public immutable aToken;
    // EthAnchor USDC conversion pool.
    IConversionPool public immutable usdcConversionPool;
    // Exchange rate feeder.
    IExchangeRateFeeder public immutable exchangeRateFeeder;

    // The mininum amount of token token to trigger position adjustment
    uint256 public minWant = 100;

    constructor(
        BaseVault _vault,
        ERC20 _aToken,
        IConversionPool _usdcConversionPool,
        IExchangeRateFeeder _exchangeRateFeeder
    ) {
        vault = _vault;
        token = vault.token();
        aToken = _aToken;
        usdcConversionPool = _usdcConversionPool;
        exchangeRateFeeder = _exchangeRateFeeder;
        // Approve transfer on the usdcConversionPool contract
        token.safeApprove(address(usdcConversionPool), type(uint256).max);
    }

    /** BALANCES
     **************************************************************************/
    function balanceOfToken() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function balanceOfATokenInToken() public view returns (uint256) {
        return aToken.balanceOf(address(this)) / exchangeRateFeeder.exchangeRateOf(address(token), false);
    }

    /** INVESTMENT
     **************************************************************************/

    function invest(uint256 amount) external override {
        token.transferFrom(msg.sender, address(this), amount);
        _depositWant(amount);
    }

    function _depositWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        usdcConversionPool.deposit(amount);
        return amount;
    }

    /** DIVESTMENT
     **************************************************************************/

    function _withdrawWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        uint256 aTokenAmount = amount * exchangeRateFeeder.exchangeRateOf(address(token), false);
        usdcConversionPool.redeem(aTokenAmount);
        return amount;
    }

    function divest(uint256 amountToFree) external override onlyVault returns (uint256) {
        // TODO: take current balance into consideration and only withdraw the amount that you need to
        if (amountToFree == 0) return 0;

        uint256 aTokenAmount = balanceOfATokenInToken();
        uint256 withdrawAmount = Math.min(amountToFree, aTokenAmount);

        uint256 withdrawnAmount = _withdrawWant(withdrawAmount);
        token.transfer(address(vault), withdrawnAmount);
        return withdrawnAmount;
    }

    /** TVL ESTIMATION
     **************************************************************************/

    function totalLockedValue() public view override returns (uint256) {
        return balanceOfToken() + balanceOfATokenInToken();
    }
}
