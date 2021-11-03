// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {alpUSDC} from "./alpUSDC.sol";

contract Vault {
    address public constant usdcAddress =
        0xe22da380ee6B445bb8273C81944ADEB6E8450422;
    address public alpUsdcAddress;

    constructor(address alpUsdcAddress_) {
        alpUsdcAddress = alpUsdcAddress_;
    }

    function balanceOf(address user)
        public
        view
        returns (uint256 usdc, uint256 alpine)
    {
        return (
            IERC20(usdcAddress).balanceOf(user),
            alpUSDC(alpUsdcAddress).balanceOf(user)
        );
    }

    // We don't need to check if user == msg.sender()
    // So long as this conract can transfer usdc from the given user, everything is fine
    function deposit(address user, uint256 amountUsdc) public {
        // transfer usdc to this contract
        IERC20 usdc = IERC20(usdcAddress);
        usdc.transferFrom(user, address(this), amountUsdc);

        // mint
        alpUSDC alp = alpUSDC(alpUsdcAddress);
        alp.mint(user, amountUsdc);
    }

    function withdraw(address user, uint256 amountAlpUsdc) public {
        // burn
        alpUSDC alp = alpUSDC(alpUsdcAddress);
        alp.burn(user, amountAlpUsdc);

        // transfer usdc out
        IERC20 usdc = IERC20(usdcAddress);
        usdc.transferFrom(address(this), user, amountAlpUsdc);
    }
}
