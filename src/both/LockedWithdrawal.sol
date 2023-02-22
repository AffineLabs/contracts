// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {BaseVault} from "../BaseVault.sol";

contract LockedWithdrawalEscrow is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 payToken;
    mapping(address => uint256) requestedTimeStamp;
    uint256 pendingDebtToken;
    uint256 slaInSeconds;
    BaseVault vault;

    /**
     * @notice Will initiate a ERC20 debt token
     * @param _payToken base token paid to user
     * @param _vault vault address attached to the withdrawl queue
     * @param sla minimum time of resolving the debt. user will be allowed to withdraw the funds
     */
    constructor(ERC20 _payToken, BaseVault _vault, uint256 sla) ERC20("DebtToken", "DT", 18) {
        payToken = _payToken;
        pendingDebtToken = 0;
        vault = _vault;
        slaInSeconds = sla;
    }

    /**
     * @notice User register to withdraw earn token
     * @param user user address
     * @param debtTokenShare amount of debt token share for the withdrawal request
     * NB: user withdrawal request will be locked until the SLA time is over.
     * NB: debtTokenShare = token_to_withdraw * price of token
     */
    function registerToWithdraw(address user, uint256 debtTokenShare) external {
        // check if the sender is valut
        require(address(vault) == msg.sender, "Unrecognized vault");

        _mint(user, debtTokenShare);
        requestedTimeStamp[user] = block.timestamp;
        pendingDebtToken += debtTokenShare;
    }

    /**
     * @notice Resolve the pending debt token after closing a position
     * @param resolvedAmount amount resolved after pay token to this contract.
     * This will increase the amount of paytoken and total supply of debt token in the pool
     * More user will be allowed to withdraw funds
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

    function redeem() external returns (uint256) {
        // check for sla
        require(requestedTimeStamp[msg.sender] + slaInSeconds <= block.timestamp, "Unresolved debts");

        // total share is total token supply  - not resolved debt token
        uint256 totalShare = totalSupply - pendingDebtToken;

        // total token supply for payment
        uint256 tokenSupply = payToken.balanceOf(address(this));

        // debt token share
        uint256 userShare = this.balanceOf(msg.sender);

        // check if the user share is resolved
        require(userShare <= totalShare, "Unresolved debts");

        // amount of token to pay to user
        uint256 tokenShare = tokenSupply.mulDivDown(userShare, totalShare);

        // transfer the amount.
        payToken.safeTransferFrom(address(this), msg.sender, tokenShare);
        // burn the user token.
        _burn(msg.sender, userShare);

        return userShare;
    }

    ///////////////////////////////////////
    // View for the user / fontend
    //////////////////////////////////////

    /**
     * @notice check if user can withdraw funds now.
     * @param user user address
     */
    function canWithdraw(address user) public view returns (bool) {
        if (requestedTimeStamp[user] + slaInSeconds <= block.timestamp) {
            return false;
        }

        uint256 totalShare = totalSupply - pendingDebtToken;

        if (totalShare < this.balanceOf(user)) {
            return false;
        }

        return false;
    }

    /**
     * @notice return the amount of share user can withdraw
     * @param user user address
     */
    function withdrawableAmount(address user) public view returns (uint256) {
        if (canWithdraw(user)) {
            return 0;
        }

        // total share is total token supply  - not resolved debt token
        uint256 totalShare = totalSupply - pendingDebtToken;

        // total token supply for payment
        uint256 tokenSupply = payToken.balanceOf(address(this));

        // debt token share
        uint256 userShare = this.balanceOf(msg.sender);

        // amount of token to pay to user
        uint256 tokenShare = tokenSupply.mulDivDown(userShare, totalShare);

        return tokenShare;
    }
}
