// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {AffineGovernable} from "src/utils/AffineGovernable.sol";

abstract contract ProfitReserveStorage is AffineGovernable {
    uint256 public profitReserveBps;

    function setProfitReserveBps(uint256 _profitReserveBps) external onlyGovernance {
        require(_profitReserveBps <= 10_000, "BV: invalid bps");
        profitReserveBps = _profitReserveBps;
    }
}
