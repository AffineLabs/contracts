// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

/*//////////////////////////////////////////////////////////////
                            AUDIT INFO
//////////////////////////////////////////////////////////////*/
/**
 * Audits:
 *     1. Nov 8, 2022, size: 27 Line
 * Extended: No
 * Changes: None
 */
contract AffineGovernable {
    /// @notice The governance address
    address public governance;

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    function _onlyGovernance() internal view {
        require(msg.sender == governance, "Only Governance.");
    }
}
