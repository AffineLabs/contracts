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
    // inital

    constructor(ERC20 _payToken, BaseVault _vault, uint256 sla) ERC20("DebtToken", "DT", 18) {
        payToken = _payToken;
        pendingDebtToken = 0;
        vault = _vault;
        slaInSeconds = sla;
    }

    function register(address vaultAddress, uint256 debtTokenShare) external {
        // check if the sender is valut
        require(address(vault) == vaultAddress, "Unrecognized vault");

        _mint(msg.sender, debtTokenShare);
        requestedTimeStamp[msg.sender] = block.timestamp;
        pendingDebtToken += debtTokenShare;
    }

    function resolveDebtToken(address vaultAddress, uint256 resolvedAmount) external {
        require(address(vault) == vaultAddress, "Unrecognized vault");

        pendingDebtToken -= resolvedAmount;
    }

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
}
