// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// upgrading contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// storage contract
import {UltraLRTStorage} from "src/vaults/restaking/UltraLRTStorage.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

contract UltraLRT is
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    AffineGovernable,
    UltraLRTStorage
{
    function initialize(address _governance) external initializer {
        governance = _governance;

        __AccessControl_init();
        __Pausable_init();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GUARDIAN_ROLE, governance);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}
}
