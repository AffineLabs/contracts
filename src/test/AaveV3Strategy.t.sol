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
contract ArbitrumAaveStratTest is AAVEStratTest {
    function _fork() internal override {
        forkArb();
    }

    function _usdc() internal override returns (address) {
        return 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    }

    function _lendingPool() internal override returns (address) {
        return 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    }

    function _deployStrategy() internal override returns (address strat) {
        strat = address(new AaveV3Strategy(vault, IPool(_lendingPool())));
    }
}
