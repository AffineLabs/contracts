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

    // Max locked withdrawal time, user can withdraw funds after sla
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
     * @param debtShares amount of debt token share for the withdrawal request
     * @dev user withdrawal request will be locked until the SLA time is over.
     * @dev debtShares = token_to_withdraw * price of token
     * @dev user will get the share of debtShare after selling earn token
     */
    function registerWithdrawalRequest(address user, uint256 debtShares) external onlyVault {
        _mint(user, debtShares);
        requestTimes[user] = block.timestamp;
        pendingDebtShares += debtShares;
    }

    /**
     * @notice Resolve the pending debt token after closing a position
     * @param resolvedAmount amount resolved after pay token to this contract.
     * @dev This will increase the amount of assets and total supply of debt token in the pool
     * @dev More user will be allowed to withdraw funds
     * @dev the resolved amount is the ratio of locked e-earn token and minimum e earn token available to burn in vault.
     * @dev resolvedAmount = pendingDebtToken * min(vault_available_e_earn_to_burn, locked_e_earn) / locked_e_earn
     */
    function resolveDebtShares(uint256 resolvedAmount) external onlyVault {
        // check if we are resolving more than pending share
        pendingDebtShares -= resolvedAmount;
    }

    /**
     * @notice calculate the total resolved debt share
     * @return total resolved debt share
     */
    function getResolvedShares() internal view returns (uint256) {
        // total share is total token supply  - not resolved debt token
        return totalSupply - pendingDebtShares;
    }

    /**
     * @notice checks if current time is before sla or not
     * @return true if calls are made by user before sla period
     */
    function beforeSLA(address user) internal view returns (bool) {
        // total share is total token supply  - not resolved debt token
        return block.timestamp < requestTimes[user] + sla;
    }

    /**
     * @notice Release all the available funds of the user.
     * @return tokenShare amount of asset user gets
     * @dev required to have enough share in debt token, As we don't have cancellation policy.
     * @dev user will get the full amount proportion of debtShare
     */
    function redeem() external returns (uint256) {
        // check for sla
        require(!beforeSLA(msg.sender), "LWE: before SLA time");

        uint256 resolvedShares = getResolvedShares();

        // debt token share
        uint256 userShares = balanceOf[msg.sender];

        // check if the user share is resolved
        require(userShares <= resolvedShares, "LWE: Unresolved debts");

        // total token supply for payment
        uint256 totalAssets = asset.balanceOf(address(this));

        // amount of asset to pay to user
        uint256 assetsToUser = totalAssets.mulDivDown(userShares, resolvedShares);

        // transfer the amount.
        asset.safeTransfer(msg.sender, assetsToUser);
        // burn the user token.
        _burn(msg.sender, userShares);

        return assetsToUser;
    }

    ///////////////////////////////////////
    ///         ERC-20 OVERRIDE
    /// overriding transfer and transferFrom
    /// to make debt token non-transferable
    ///////////////////////////////////////

    /**
     * @dev Token is non transferable
     */
    function transfer(address to, uint256 amount) public override returns (bool) {}
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {}

    ///////////////////////////////////////
    // View for the user / font-end
    //////////////////////////////////////

    /**
     * @notice check if user can withdraw funds now.
     * @return true or false if user can withdraw the funds or not
     */
    function canWithdraw(address user) public view returns (bool) {
        if (beforeSLA(user)) {
            return false;
        }

        uint256 resolvedShares = getResolvedShares();

        if (resolvedShares < balanceOf[user]) {
            return false;
        }

        return true;
    }

    /**
     * @notice return the amount of share user can withdraw
     * @return returns withdrawable asset amount
     */
    function withdrawableAmount(address user) public view returns (uint256) {
        if (!canWithdraw(user)) {
            return 0;
        }

        uint256 resolvedShares = getResolvedShares();

        // total token supply for payment
        uint256 totalAssets = asset.balanceOf(address(this));

        // debt token share
        uint256 userShares = balanceOf[user];

        // amount of token to pay to user
        uint256 assetsToUser = totalAssets.mulDivDown(userShares, resolvedShares);

        return assetsToUser;
    }
}
