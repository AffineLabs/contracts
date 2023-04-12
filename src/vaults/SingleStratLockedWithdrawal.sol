// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {Vault} from "src/vaults/Vault.sol";

contract LockedWithdrawalEscrow {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // Epoch counter
    uint256 public currentEpoch;

    // token paid to user
    ERC20 public immutable asset;

    // Vault this escrow attached to
    Vault public immutable vault;

    // map each user with
    mapping(uint256 => mapping(address => uint256)) public userDebtShare;

    // map price for each epoch
    mapping(uint256 => uint256) epochPrice;

    // last resolved time
    uint256 public lastResolvedUTCTime;

    constructor(Vault _vault) {
        asset = ERC20(_vault.asset());
        vault = _vault;
    }

    modifier onlyVault() {
        require(msg.sender == address(vault), "LWE: must be vault");
        _;
    }
    // register user withdrawal request as debt

    function registerWithdrawalRequest(address user, uint256 shares) external onlyVault {
        // lock user share
        vault.transferFrom(user, address(this), shares);
        userDebtShare[currentEpoch][user] += shares;
    }

    // dummy function to work with, replaced by vault modification PR
    function availableToWithdraw(uint256 shares) internal returns (bool) {
        return shares > 0;
    }

    // this will swap the shares with vault and receive assets
    function resolveDebtShares() external onlyVault {
        uint256 shares = vault.balanceOf(address(this));
        uint256 preAssets = asset.balanceOf(address(this));
        // check for availability of
        if (!availableToWithdraw(shares)) {
            return;
        }
        // redeem the shares
        vault.redeem(vault.balanceOf(address(this)), address(this), address(this));

        uint256 postAssets = asset.balanceOf(address(this));

        epochPrice[currentEpoch] = (postAssets - preAssets).mulDivDown(1, shares);
        // move to next epoch
        currentEpoch++;
    }

    function redeem(address user, uint256 epoch) external returns (uint256) {
        // Should be resolved epoch
        require(epoch <= currentEpoch, "LWE: epoch not resolved.");

        // total assets for user
        uint256 assets = epochPrice[epoch] * userDebtShare[epoch][user];

        // check for asset balance
        require(assets <= asset.balanceOf(address(this)), "LWE: Not enough asset.");

        // reset the user debt share
        userDebtShare[epoch][user] = 0;

        // transfer asset to user
        asset.transfer(user, assets);
        return assets;
    }

    function canWithdraw(uint256 epoch) public view returns (bool) {
        return epoch <= currentEpoch;
    }

    // return withdrawable assets for a user
    function withdrawableAssets(address user, uint256 epoch) public view returns (uint256) {
        if (!canWithdraw(epoch)) {
            return 0;
        }
        return epochPrice[epoch] * userDebtShare[epoch][user];
    }

    // return withdrawable assets for a user
    function withdrawableShares(address user, uint256 epoch) public view returns (uint256) {
        if (!canWithdraw(epoch)) {
            return 0;
        }
        return userDebtShare[epoch][user];
    }
}
