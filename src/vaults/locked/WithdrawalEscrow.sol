// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";

contract WithdrawalEscrow {
    using FixedPointMathLib for uint256;

    // token paid to user
    ERC20 public immutable asset;

    // Vault this escrow attached to
    StrategyVault public immutable vault;

    // per epoch per user debt shares
    mapping(uint256 => mapping(address => uint256)) public userDebtShare;

    struct EpochInfo {
        uint256 shares;
        uint256 assets;
    }
    // map per epoch debt share

    mapping(uint256 => EpochInfo) public epochInfo;

    constructor(StrategyVault _vault) {
        asset = ERC20(_vault.asset());
        vault = _vault;
    }

    modifier onlyVault() {
        require(msg.sender == address(vault), "SSWE: must be vault");
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
        //@ lock user share need to be done from vault, otherwise need approval from user
        // vault.transferFrom(user, address(this), shares);
        // register shares of the user

        uint256 currentEpoch = vault.epoch();
        userDebtShare[currentEpoch][user] += shares;

        epochInfo[currentEpoch].shares += shares;

        emit WithdrawalRequest(user, currentEpoch, shares);
    }

    /**
     * @notice resolve the locked shares for current epoch
     * @dev This function will be triggered after closing a position
     * @dev will check for available shares to burn
     * @dev after resolving vault will send the assets to escrow and burn the share
     */
    function resolveDebtShares() external onlyVault {
        // redeem vault shares and receive assets
        uint256 assets =
            vault.redeem({shares: vault.balanceOf(address(this)), receiver: address(this), owner: address(this)});

        uint256 currentEpoch = vault.epoch();
        epochInfo[currentEpoch].assets = assets;
    }
    /**
     * @notice Convert epoch shares to assets
     * @param user address
     * @param epoch withdrawal request epoch
     * @return converted assets
     */

    function _epochSharesToAssets(address user, uint256 epoch) internal view returns (uint256) {
        uint256 userShares = userDebtShare[epoch][user];
        EpochInfo memory data = epochInfo[epoch];
        return (data.assets * userShares) / data.shares;
    }
    /**
     * @notice Redeem withdrawal request
     * @param user address
     * @param epoch withdrawal request epoch
     * @return received assets
     */

    function redeem(address user, uint256 epoch) external returns (uint256) {
        // Should be a resolved epoch
        require(canWithdraw(epoch), "SSWE: epoch not resolved.");

        // total assets for user
        uint256 assets = _epochSharesToAssets(user, epoch);

        // reset the user debt share
        userDebtShare[epoch][user] = 0;

        // transfer asset to user
        asset.transfer(user, assets);
        return assets;
    }

    /**
     * @notice Check if an epoch is resolved or not
     * @param epoch epoch number
     * @return true if epoch is resolved
     */
    function canWithdraw(uint256 epoch) public view returns (bool) {
        uint256 currentEpoch = vault.epoch();
        return epoch < currentEpoch || epoch == currentEpoch && vault.epochEnded();
    }
    /**
     * @notice Get withdrawable assets of a user
     * @param user user address
     * @param epoch requests epoch
     * @return amount of assets user will receive
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

    function getAssets(address user, uint256[] calldata epochs) public view returns (uint256 assets) {
        for (uint256 i = 0; i < epochs.length; i++) {
            assets += withdrawableAssets(user, epochs[i]);
        }
        return assets;
    }
}
