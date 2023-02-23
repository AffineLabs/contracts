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
    ERC20 immutable asset;

    // Last withdrawal request time map
    mapping(address => uint256) requestTimes;

    // amount of pending debt token share to resolve
    // The share assigned to the user immediately, need to keep track of it until resolved.
    uint256 pendingDebtToken;

    // Max locked withdrawal time, user can withdaraw funds after sla
    uint256 immutable sla;

    AffineVault vault;

    constructor(AffineVault _vault, uint256 _sla) ERC20("DebtToken", "DT", 18) {
        asset = ERC20(_vault.asset());
        vault = _vault;
        sla = _sla;
    }

    /**
     * @notice User register to withdraw earn token
     * @param user user address
     * @param debtShare amount of debt token share for the withdrawal request
     * NB: user withdrawal request will be locked until the SLA time is over.
     * NB: debtTokenShare = token_to_withdraw * price of token
     */
    function registerWithdrawalRequest(address user, uint256 debtShare) external {
        // check if the sender is valut
        require(address(vault) == msg.sender, "Unrecognized vault");

        _mint(user, debtShare);
        requestTimes[user] = block.timestamp;
        pendingDebtToken += debtShare;
    }

    /**
     * @notice Resolve the pending debt token after closing a position
     * @param resolvedAmount amount resolved after pay token to this contract.
     * This will increase the amount of paytoken and total supply of debt token in the pool
     * More user will be allowed to withdraw funds
     *
     *  NB: the resolved amount is the ratio of locked e-earn token and minimun e earn token
     *  available to burn in vault.
     *
     *  resolvedAmount = pendinDebtToken * min(vault_available_e_earn_to_burn, locked_e_earn) / locked_e_earn
     */
    function resolveDebtToken(uint256 resolvedAmount) external {
        require(address(vault) == msg.sender, "Unrecognized vault");
        pendingDebtToken -= resolvedAmount;
    }
    /**
     * @notice Release all the available funds of the user.
     *     NB: required to have enough share in debt token.
     *     As we dont have cancellation policy then
     */

    function redeem() public returns (uint256) {
        // check for sla
        require(requestTimes[msg.sender] + sla <= block.timestamp, "Unresolved debts");

        // total share is total token supply  - not resolved debt token
        uint256 totalShare = totalSupply - pendingDebtToken;

        // debt token share
        uint256 userShare = balanceOf[msg.sender];

        // check if the user share is resolved
        require(userShare <= totalShare, "Unresolved debts");

        // total token supply for payment
        uint256 tokenSupply = asset.balanceOf(address(this));

        // amount of token to pay to user
        uint256 tokenShare = tokenSupply.mulDivDown(userShare, totalShare);

        // transfer the amount.
        // asset.safeTransfer(msg.sender, tokenShare);
        asset.safeTransfer(msg.sender, tokenShare);
        // burn the user token.
        _burn(msg.sender, userShare);

        return userShare;
    }

    ///////////////////////////////////////
    // View for the user / fontend
    //////////////////////////////////////

    /**
     * @notice check if user can withdraw funds now.
     */
    function canWithdraw() public view returns (bool) {
        if (requestTimes[msg.sender] + sla <= block.timestamp) {
            return false;
        }

        uint256 totalShare = totalSupply - pendingDebtToken;

        if (totalShare < balanceOf[msg.sender]) {
            return false;
        }

        return false;
    }

    /**
     * @notice return the amount of share user can withdraw
     */
    function withdrawableAmount() public view returns (uint256) {
        if (canWithdraw()) {
            return 0;
        }

        // total share is total token supply  - not resolved debt token
        uint256 totalShare = totalSupply - pendingDebtToken;

        // total token supply for payment
        uint256 tokenSupply = asset.balanceOf(address(this));

        // debt token share
        uint256 userShare = balanceOf[msg.sender];

        // amount of token to pay to user
        uint256 tokenShare = tokenSupply.mulDivDown(userShare, totalShare);

        return tokenShare;
    }
}
