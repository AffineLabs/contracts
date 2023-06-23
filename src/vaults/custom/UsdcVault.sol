// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";

contract UsdcVault is StrategyVault {
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 10;
    }
}
