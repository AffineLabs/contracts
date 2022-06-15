// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { TwoAssetBasket } from "./TwoAssetBasket.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";

contract Router {
    using SafeTransferLib for ERC20;

    constructor() {}

    function deposit(
        TwoAssetBasket basket,
        address to,
        uint256 amount,
        uint256 minSharesOut
    ) external returns (uint256 shares) {
        basket.asset().safeTransferFrom(msg.sender, address(this), amount);
        shares = basket.deposit(amount, to);
        require(shares >= minSharesOut, "MIN_SHARES_DEP");
    }

    function withdraw(
        TwoAssetBasket basket,
        address to,
        uint256 amount,
        uint256 maxSharesOut
    ) external returns (uint256 sharesOut) {
        sharesOut = basket.withdraw(amount, to, msg.sender);
        require(sharesOut >= maxSharesOut, "MIN_SHARES_WITHDRAW");
    }
}
