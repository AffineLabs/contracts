// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {OmniUltraLRT} from "src/vaults/restaking/omni-lrt/OmniUltraLRT.sol";

/**
 * @title WithdrawalEscrowV2
 * @dev Escrow contract for withdrawal requests
 */
contract OmniWithdrawalEscrow {
    using SafeTransferLib for ERC20;

    /// @notice The vault asset.
    ERC20 public immutable asset;

    /// @notice The vault this escrow attached to.
    OmniUltraLRT public immutable vault;

    // per epoch per user debt shares
    mapping(uint256 => mapping(address => uint256)) public userDebtShare;

    struct EpochInfo {
        uint128 shares;
        uint128 assets;
        uint128 resolvedShares;
    }

    uint256 public currentEpoch;
    uint256 public resolvingEpoch;
    uint256 public totalDebt;
    uint256 public totalAssets;
    bool public shareWithdrawable;

    // map per epoch debt share
    mapping(uint256 => EpochInfo) public epochInfo;

    /**
     * @param _vault UltraLRT vault address
     */
    constructor(OmniUltraLRT _vault, address _asset) {
        vault = _vault;
        asset = ERC20(_asset);

        // todo: require asset and vault validity check
    }

    /**
     * @notice Modifier to allow function calls only from the vault
     */
    modifier onlyVault() {
        require(msg.sender == address(vault), "WE: must be vault");
        _;
    }

    /**
     * @notice Modifier to allow function calls only from the governance
     */
    modifier onlyGovernance() {
        require(msg.sender == address(vault.governance()), "WE: Must be gov");
        _;
    }

    /**
     * @notice Withdrawal Request event
     * @param user user address
     * @param epoch epoch of the request
     * @param shares withdrawal vault shares
     * @dev will makes things easy to search for each user withdrawal requests
     */
    event WithdrawalRequest(address indexed user, uint256 epoch, uint256 shares);

    /**
     * @notice Register withdrawal request as debt
     * @param user user address
     * @param shares amount of vault shares user requested to withdraw
     */
    function registerWithdrawalRequest(address user, uint256 shares) external onlyVault {
        // register shares of the user

        userDebtShare[currentEpoch][user] += shares;
        epochInfo[currentEpoch].shares += uint128(shares);

        totalDebt += shares;

        emit WithdrawalRequest(user, currentEpoch, shares);
    }

    /**
     * @notice End the epoch
     * @dev will be called by the vault after closing a position
     */
    function endEpoch() external onlyVault {
        if (epochInfo[currentEpoch].shares == 0) {
            return;
        }

        currentEpoch = currentEpoch + 1;
        // TODO: epoch end event
    }

    /**
     * @notice Get the debt to resolve
     * @return amount of debt to resolve
     */
    function getDebtToResolve() external view returns (uint256) {
        return resolvingEpoch < currentEpoch
            ? epochInfo[resolvingEpoch].shares - epochInfo[resolvingEpoch].resolvedShares
            : 0;
    }

    /**
     * @notice resolve the locked shares for current epoch
     * @dev This function will be triggered after closing a position
     * @dev will check for available shares to burn
     * @dev after resolving vault will send the assets to escrow and burn the share
     */
    function resolveDebtShares(uint256 shares, uint256 amount) external onlyVault {
        require(resolvingEpoch < currentEpoch, "WEV2: No debt.");

        EpochInfo memory data = epochInfo[resolvingEpoch];

        require(data.shares >= (shares + data.resolvedShares), "WEV2: Invalid shares.");

        // receive token from vault
        asset.safeTransferFrom(address(vault), address(this), amount);

        totalDebt -= shares;
        epochInfo[resolvingEpoch].assets += uint128(amount);

        // update the resolved shares
        epochInfo[resolvingEpoch].resolvedShares += uint128(shares);

        if (data.shares == data.resolvedShares) {
            resolvingEpoch += 1;
        }
    }

    // enable share withdrawal

    /**
     * @notice Enable share withdrawal
     */
    function enableShareWithdrawal() external onlyVault {
        shareWithdrawable = true;
    }

    /**
     * @notice Disable share withdrawal
     */
    function disableShareWithdrawal() external onlyGovernance {
        shareWithdrawable = false;
    }

    /**
     * @notice Redeem multiple epochs
     * @param user user address
     * @param epochs withdrawal request epochs
     * @return assets received
     */
    function redeemMultiEpoch(address user, uint256[] calldata epochs) public returns (uint256 assets) {
        for (uint8 i = 0; i < epochs.length; i++) {
            assets += redeem(user, epochs[i]);
        }
    }
    /**
     * @notice Redeem withdrawal request
     * @param user address
     * @param epoch withdrawal request epoch
     * @return received assets
     */

    function redeem(address user, uint256 epoch) public returns (uint256) {
        // Should be a resolved epoch
        require(canWithdraw(epoch), "WE: epoch not resolved.");

        // total assets for user
        (uint256 shares, uint256 assets) = _epochSharesToAssets(user, epoch);
        require(assets > 0, "WE: no assets to redeem");

        // reset the user debt share
        userDebtShare[epoch][user] -= shares;

        // Transfer asset to user
        asset.safeTransfer(user, assets);

        // update epoch info
        EpochInfo storage data = epochInfo[epoch];

        data.shares -= uint128(shares);
        data.assets -= uint128(assets);
        data.resolvedShares -= uint128(shares);

        epochInfo[epoch] = data;

        return assets;
    }

    function redeemShares(address user, uint256 epoch) public returns (uint256) {
        require(shareWithdrawable, "WE: share withdrawal disabled");

        // max share amount can withdraw
        uint256 shares = Math.min(userDebtShare[epoch][user], epochInfo[epoch].shares - epochInfo[epoch].resolvedShares);

        require(shares > 0, "WE: no shares to redeem");

        // reset the user debt share
        userDebtShare[epoch][user] -= shares;

        // transfer assets to user
        ERC20(address(vault)).safeTransfer(user, shares);

        // update epoch info
        epochInfo[epoch].shares -= uint128(shares);

        if (epochInfo[epoch].resolvedShares == epochInfo[epoch].shares) {
            resolvingEpoch += 1;
        }
        return shares;
    }

    /**
     * @notice Convert epoch shares to assets
     * @param user User address
     * @param epoch withdrawal request epoch
     * @return shares
     * @return assets
     */
    function _epochSharesToAssets(address user, uint256 epoch) internal view returns (uint256 shares, uint256 assets) {
        uint256 userShares = userDebtShare[epoch][user];
        EpochInfo memory data = epochInfo[epoch];

        shares = Math.min(userShares, data.resolvedShares);
        assets = ((shares * data.assets) / data.resolvedShares);
    }

    /**
     * @notice Check if an epoch is completed or not
     * @param epoch Epoch number
     * @return True if epoch is completed
     */
    function canWithdraw(uint256 epoch) public view returns (bool) {
        return epoch < resolvingEpoch || (epoch == resolvingEpoch && epochInfo[epoch].resolvedShares > 0);
    }
    /**
     * @notice Get withdrawable assets of a user
     * @param user User address
     * @param epoch The vault epoch
     * @return Amount of assets user will receive
     */

    function withdrawableAssets(address user, uint256 epoch) public view returns (uint256) {
        if (!canWithdraw(epoch)) {
            return 0;
        }
        (, uint256 assets) = _epochSharesToAssets(user, epoch);
        return assets;
    }

    /**
     * @notice Get withdrawable shares of a user
     * @param user user address
     * @param epoch requests epoch
     * @return amount of shares to withdraw
     */
    function withdrawableShares(address user, uint256 epoch) public view returns (uint256) {
        if (!canWithdraw(epoch)) {
            return 0;
        }
        if (epoch == resolvingEpoch && epochInfo[epoch].resolvedShares < epochInfo[epoch].shares) {
            return Math.min(userDebtShare[epoch][user], epochInfo[epoch].resolvedShares);
        }
        return userDebtShare[epoch][user];
    }

    /**
     * @notice Get total withdrawable assets of a user for multiple epochs
     * @param user User address
     * @param epochs withdrawal request epochs
     * @return assets total withdrawable assets
     */
    function getAssets(address user, uint256[] calldata epochs) public view returns (uint256 assets) {
        for (uint256 i = 0; i < epochs.length; i++) {
            assets += withdrawableAssets(user, epochs[i]);
        }
        return assets;
    }

    /**
     * @notice sweep the assets to governance
     * @param _asset Asset address
     * @dev only use case in case of emergency
     */
    function sweep(address _asset) external onlyGovernance {
        ERC20(_asset).safeTransfer(vault.governance(), ERC20(_asset).balanceOf(address(this)));
    }
}
