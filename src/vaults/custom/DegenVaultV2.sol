// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {StrategyVaultV2} from "src/vaults/locked/StrategyVaultV2.sol";

contract DegenVaultV2 is StrategyVaultV2 {
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 10;
    }
}

contract DegenVaultV2Eth is StrategyVaultV2 {
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 10;
    }
}

contract HighYieldLpVaultEth is StrategyVaultV2 {
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 10;
    }
}
