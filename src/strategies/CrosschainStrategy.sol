// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "./AccessStrategy.sol";
import {uncheckedInc} from "src/libs/Unchecked.sol";

contract CrosschainStrategy is AccessStrategy {
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST");

    constructor(AffineVault _vault, address[] memory strategists) AccessStrategy(_vault, strategists) {
        // Governance is admin
        _grantRole(DEFAULT_ADMIN_ROLE, vault.governance());
        _grantRole(STRATEGIST_ROLE, vault.governance());

        // Give STRATEGIST_ROLE to every address in list
        for (uint256 i = 0; i < strategists.length; i = uncheckedInc(i)) {
            _grantRole(STRATEGIST_ROLE, strategists[i]);
        }
    }

    function divest() external virtual override returns (uint256) {
        return 0;
    }

    function totalLockedValue() external virtual override returns (uint256) {
        return 0;
    }
}
