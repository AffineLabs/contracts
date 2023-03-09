// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {LockedWithdrawalEscrow} from "src/vaults/LockedWithdrawalEscrow.sol";

contract VaultV2Storage {
    /// @notice The locked-withdrawal escrow contract
    LockedWithdrawalEscrow public debtEscrow;
    uint256 public pendingDebt;
    uint256 public totalStrategyDebt;
}
