// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

contract AffineGovernable {
    /// @notice The governance address
    address public governance;
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only Governance.");
        _;
    }
}
