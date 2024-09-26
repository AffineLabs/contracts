// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

/**
 * @title WithdrawalEscrowV2
 * @dev Escrow contract for withdrawal requests
 */
contract OmniWithdrawalEscrow {
    using SafeTransferLib for ERC20;

    /// @notice The vault asset.
    ERC20 public immutable asset;

    /// @notice The vault this escrow attached to.
    UltraLRT public immutable vault;

    // per epoch per user debt shares
    mapping(uint256 => mapping(address => uint256)) public userDebtShare;

    struct EpochInfo {
        uint128 shares;
        uint128 assets;
    }

    uint256 public currentEpoch;
    uint256 public resolvingEpoch;
    uint256 public totalDebt;
    uint256 public totalAssets;

    // map per epoch debt share
    mapping(uint256 => EpochInfo) public epochInfo;

    /**
     * @param _vault UltraLRT vault address
     */
    constructor(UltraLRT _vault, address _asset) {
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
        require(epochInfo[currentEpoch].shares > 0, "WEV2: No Debt.");

        currentEpoch = currentEpoch + 1;
        // TODO: epoch end event
    }

    /**
     * @notice Get the debt to resolve
     * @return amount of debt to resolve
     */
    function getDebtToResolve() external view returns (uint256) {
        return resolvingEpoch < currentEpoch ? epochInfo[resolvingEpoch].shares : 0;
    }

    /**
     * @notice resolve the locked shares for current epoch
     * @dev This function will be triggered after closing a position
     * @dev will check for available shares to burn
     * @dev after resolving vault will send the assets to escrow and burn the share
     */
    function resolveDebtShares(uint256 amount) external onlyVault {
        require(resolvingEpoch < currentEpoch, "WEV2: No debt.");

        // receive token from vault
        asset.safeTransferFrom(address(vault), address(this), amount);

        totalDebt -= epochInfo[resolvingEpoch].shares;
        epochInfo[resolvingEpoch].assets = uint128(amount);

        resolvingEpoch += 1;
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
        uint256 assets = _epochSharesToAssets(user, epoch);
        require(assets > 0, "WE: no assets to redeem");

        // reset the user debt share
        userDebtShare[epoch][user] = 0;

        // Transfer asset to user
        asset.safeTransfer(user, assets);
        return assets;
    }

    /**
     * @notice Convert epoch shares to assets
     * @param user User address
     * @param epoch withdrawal request epoch
     * @return converted assets
     */
    function _epochSharesToAssets(address user, uint256 epoch) internal view returns (uint256) {
        uint256 userShares = userDebtShare[epoch][user];
        EpochInfo memory data = epochInfo[epoch];
        return (userShares * data.assets) / data.shares;
    }

    /**
     * @notice Check if an epoch is completed or not
     * @param epoch Epoch number
     * @return True if epoch is completed
     */
    function canWithdraw(uint256 epoch) public view returns (bool) {
        return epoch < resolvingEpoch;
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
        return _epochSharesToAssets(user, epoch);
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
