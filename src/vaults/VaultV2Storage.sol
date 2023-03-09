// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ILockedWithdrawalEscrow} from "src/interfaces/ILockedWithdrawalEscrow.sol";

contract VaultV2Storage {
    /// @notice The ILockedWithdrawalEscrow contract
    ILockedWithdrawalEscrow public debtEscrow;
    uint256 public pendingDebt;
    uint256 public totalStrategyDebt;
}
