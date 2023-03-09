// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

contract DebtStrategy is AccessStrategy {
    using SafeTransferLib for ERC20;

    // amount of debt strategy has
    uint256 public debt;

    constructor(AffineVault _vault, address[] memory strategists) AccessStrategy(_vault, strategists) {}

    function divest(uint256 amount) external override onlyVault returns (uint256) {
        // withdraw funds
        uint256 divestedAmount = _divest(amount);

        // settle debt
        // debt+amount is total debt as there might be existing debt.
        if (asset.balanceOf(address(this)) < (debt + amount)) {
            debt += amount;
        } else {
            asset.safeTransfer(address(vault), debt + amount);
            debt = 0;
        }

        return divestedAmount;
    }

    /**
     * @notice transfer assets to vault to resolve debts
     */
    function settleDebt() external onlyRole(STRATEGIST_ROLE) {
        // max possible amount to settle
        uint256 settleAmount = Math.min(asset.balanceOf(address(this)), debt);
        // transfer asset to vault
        asset.safeTransfer(address(vault), settleAmount);

        // update remaining debt amount
        debt -= settleAmount;
    }

    /**
     * @notice reset the debt amount to zero
     * @dev purpose of this if strategy lost assets and can not pay the full debt
     */
    function resetDebt() external onlyVault {
        debt = 0;
    }
}
