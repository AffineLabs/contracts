// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {BridgeEscrow} from "src/vaults/cross-chain-vault/escrow/BridgeEscrow.sol";
import {AaveV3Strategy, IPool} from "src/strategies/AaveV3Strategy.sol";

import {AAVEStratTest} from "./AaveV2Strategy.t.sol";

/// @notice Test AAVE strategy
contract BaseAaveStratTest is AAVEStratTest {
    function _fork() internal override {
        forkBase();
    }

    function _usdc() internal override returns (address) {
        return 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    }

    function _lendingPool() internal override returns (address) {
        return 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    }

    function _deployStrategy() internal override returns (address strat) {
        strat = address(new AaveV3Strategy(vault, IPool(_lendingPool())));
    }
}
