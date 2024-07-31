// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

import {IDefaultCollateral as ISymCollateral} from "src/interfaces/symbiotic/IDefaultCollateral.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";

/**
 * @title SymbioticDelegator
 * @dev Delegator contract for wStETH on Symbiotic
 */
contract SymbioticDelegator is Initializable, AffineDelegator, AffineGovernable {
    using SafeTransferLib for ERC20;

    ISymCollateral public collateral;

    /**
     * @dev Initialize the contract
     * @param _vault Vault address
     * @param _collateral Collateral address
     */
    function initialize(address _vault, address _collateral) external initializer {
        vault = _vault;
        governance = UltraLRT(vault).governance();
        asset = ERC20(UltraLRT(vault).asset());
        collateral = ISymCollateral(_collateral);

        // @dev check the asset
        require(UltraLRT(vault).asset() == collateral.asset(), "SYMD: invalid asset");
        asset.safeApprove(_collateral, type(uint256).max);
    }

    /**
     * @notice Delegate & restake wStETH to operator on Symbiotic
     * @param amount Amount to delegate
     */
    function _delegate(uint256 amount) internal override {
        collateral.deposit(address(this), amount);
    }

    /**
     * @notice Request withdrawal from Symbiotic
     * @param assets Amount to withdraw
     */
    function _requestWithdrawal(uint256 assets) internal override {
        collateral.withdraw(address(this), assets);
    }

    /**
     * @notice Get the withdrawable assets
     * @return withdrawable assets
     */
    function withdrawableAssets() public view override returns (uint256) {
        return collateral.balanceOf(address(this));
    }

    /**
     * @notice Get the queued assets
     * @return queued assets
     */
    function queuedAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
