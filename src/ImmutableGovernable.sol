// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

contract ImmutableGovernable {
    /// @notice The governance address
    address public immutable governance;

    constructor(address _gov) {
        governance = _gov;
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    function _onlyGovernance() internal view {
        require(msg.sender == governance, "Only Governance.");
    }
}
