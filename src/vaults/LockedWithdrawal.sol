// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";

contract LockedWithdrawalEscrow is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // token paid to user
    ERC20 public immutable asset;

    // Last withdrawal request time map
    mapping(address => uint256) public requestTimes;

    // amount of pending debt token share to resolve
    uint256 public pendingDebtShares;

    // Max locked withdrawal time, user can withdaraw funds after sla
    uint256 public immutable sla;

    // Vault this escrow attached to
    AffineVault public immutable vault;

    constructor(AffineVault _vault, uint256 _sla) ERC20("DebtToken", "DT", 18) {
        asset = ERC20(_vault.asset());
        vault = _vault;
        sla = _sla;
    }

    modifier onlyVault() {
        require(msg.sender == address(vault), "LWE: must be vault");
        _;
    }

    /**
     * @notice User register to withdraw earn token
     * @param user user address
     * @param debtShare amount of debt token share for the withdrawal request
     * @dev user withdrawal request will be locked until the SLA time is over.
     * @dev debtShare = token_to_withdraw * price of token
     * @dev user will get the share of debtShare after selling earn token
     */
    function registerWithdrawalRequest(address user, uint256 debtShare) external onlyVault {
        _mint(user, debtShare);
        requestTimes[user] = block.timestamp;
        pendingDebtShares += debtShare;
    }

    /**
     * @notice Resolve the pending debt token after closing a position
     * @param resolvedAmount amount resolved after pay token to this contract.
     * @dev This will increase the amount of paytoken and total supply of debt token in the pool
     * @dev More user will be allowed to withdraw funds
     * @dev the resolved amount is the ratio of locked e-earn token and minimun e earn token available to burn in vault.
     * @dev resolvedAmount = pendinDebtToken * min(vault_available_e_earn_to_burn, locked_e_earn) / locked_e_earn
     */
    function resolveDebtShares(uint256 resolvedAmount) external onlyVault {
        pendingDebtShares -= resolvedAmount;
    }

    /**
     * @notice calculate the total resolved debt share
     * @return total resoved debt share
     */
    function getTotalShare() internal view returns (uint256) {
        // total share is total token supply  - not resolved debt token
        return totalSupply - pendingDebtShares;
    }

    /**
     * @notice Release all the available funds of the user.
     * @return tokenShare amount of asset user gets
     * @dev required to have enough share in debt token, As we dont have cancellation policy.
     * @dev user will get the full amount proportion of debtShare
     */
    function redeem() external returns (uint256) {
        // check for sla
        require(block.timestamp > requestTimes[msg.sender] + sla, "LWE: before SLA time");

        uint256 totalShare = getTotalShare();

        // debt token share
        uint256 userShare = balanceOf[msg.sender];

        // check if the user share is resolved
        require(userShare <= totalShare, "LWE: Unresolved debts");

        // total token supply for payment
        uint256 totalAssets = asset.balanceOf(address(this));

        // amount of asset to pay to user
        uint256 assetToUser = totalAssets.mulDivDown(userShare, totalShare);

        // transfer the amount.
        asset.safeTransfer(msg.sender, assetToUser);
        // burn the user token.
        _burn(msg.sender, userShare);

        return assetToUser;
    }

    ///////////////////////////////////////
    // View for the user / fontend
    //////////////////////////////////////

    /**
     * @notice check if user can withdraw funds now.
     * @return true or false if user can withdraw the funds or not
     */
    function canWithdraw() public view returns (bool) {
        if (block.timestamp < requestTimes[msg.sender] + sla) {
            return false;
        }

        uint256 totalShare = getTotalShare();

        if (totalShare < balanceOf[msg.sender]) {
            return false;
        }

        return true;
    }

    /**
     * @notice return the amount of share user can withdraw
     * @return returns withdrawable asset amount
     */
    function withdrawableAmount() public view returns (uint256) {
        if (!canWithdraw()) {
            return 0;
        }

        uint256 totalShare = getTotalShare();

        // total token supply for payment
        uint256 totalAssets = asset.balanceOf(address(this));

        // debt token share
        uint256 userShare = balanceOf[msg.sender];

        // amount of token to pay to user
        uint256 assetToUser = totalAssets.mulDivDown(userShare, totalShare);

        return assetToUser;
    }
}
