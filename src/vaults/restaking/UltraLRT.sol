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
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

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
    function initialize(address _governance, address vaultAsset, string memory _name, string memory _symbol)
        external
        initializer
    {
        governance = _governance;

        // init token
        __ERC4626_init(IERC20MetadataUpgradeable(vaultAsset));
        __ERC20_init(_name, _symbol);

        // init control
        __AccessControl_init();
        __Pausable_init();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GUARDIAN_ROLE, governance);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @notice Pause the contract
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /*//////////////////////////////////////////////////////////////
                            DECIMALS
    //////////////////////////////////////////////////////////////*/

    /// @dev E.g. if the asset has 18 decimals, and initialSharesPerAsset is 1e8, then the vault has 26 decimals. And
    /// "one" `asset` will be worth "one" share (where "one" means 10 ** token.decimals()).
    function decimals() public view virtual override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return ERC20(asset()).decimals() + _initialShareDecimals();
    }

    /// @notice The amount of shares to mint per wei of `asset` at genesis.
    function initialSharesPerAsset() public pure virtual returns (uint256) {
        return 10 ** _initialShareDecimals();
    }

    /// @notice Each wei of `asset` at genesis is worth 10 ** (initialShareDecimals) shares.
    function _initialShareDecimals() internal pure virtual returns (uint8) {
        return 8;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            DELEGATOR 
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            TVL
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                  FEES
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;

    event ManagementFeeSet(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeSet(uint256 oldFee, uint256 newFee);

    function setManagementFee(uint256 feeBps) external onlyGovernance {
        emit ManagementFeeSet({oldFee: managementFee, newFee: feeBps});
        managementFee = feeBps;
    }

    function setWithdrawalFee(uint256 feeBps) external onlyGovernance {
        emit WithdrawalFeeSet({oldFee: withdrawalFee, newFee: feeBps});
        withdrawalFee = feeBps;
    }
}
