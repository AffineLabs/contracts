// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC721} from "solmate/src/tokens/ERC721.sol";
import {AffineGovernable} from "src/utils/AffineGovernable.sol";

abstract contract HarvestStorage is AffineGovernable {
    uint128 public performanceFeeBps;
    uint128 public accumulatedPerformanceFee;

    function setPerformanceFeeBps(uint128 _newFeeBps) external onlyGovernance {
        performanceFeeBps = _newFeeBps;
    }

    event PerformanceFeeWithdrawn(uint256 amount);

}
