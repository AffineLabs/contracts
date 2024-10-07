// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

/* solhint-disable */

import {IPriceFeed} from "./IPriceFeed.sol";

// todo implement a real price feed
contract PriceFeed is IPriceFeed {
    uint256 public rate;
    uint256 public timestamp;

    function getPrice() external view override returns (uint256, uint256) {
        return (rate, timestamp);
    }
}
