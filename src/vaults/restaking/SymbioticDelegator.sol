// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

import {IDefaultCollateral as ISymCollateral} from "src/interfaces/symbiotic/IDefaultCollateral.sol";

contract SymbioticDelegator is Initializable, AffineGovernable {
    using SafeTransferLib for ERC20;

    UltraLRT vault;
    ERC20 asset;
    ISymCollateral collateral;

    function initialize(address _vault, address _collateral) external initializer {
        vault = UltraLRT(_vault);
        governance = vault.governance();
        asset = ERC20(vault.asset());
        collateral = ISymCollateral(_collateral);

        // @dev check the asset
        require(vault.asset() == collateral.asset(), "SYMD: invalid asset");
        asset.safeApprove(_collateral, type(uint256).max);
    }

    modifier onlyVaultOrHarvester() {
        require(
            vault.hasRole(vault.HARVESTER(), msg.sender) || msg.sender == address(vault),
            "AffineDelegator: Not a vault or harvester"
        );
        _;
    }

    function delegate(uint256 amount) external onlyVaultOrHarvester {
        asset.safeTransferFrom(address(vault), address(this), amount);
        collateral.deposit(address(this), amount);
    }

    function requestWithdrawal(uint256 assets) external onlyVaultOrHarvester {
        collateral.withdraw(address(this), assets);
    }

    /**
     * @dev Withdraw stETH from delegator to vault
     */
    function withdraw() external onlyVaultOrHarvester {
        asset.safeTransfer(address(vault), asset.balanceOf(address(this)));
    }

    // view functions
    function totalLockedValue() public view returns (uint256) {
        return withdrawableAssets() + queuedAssets();
    }

    function withdrawableAssets() public view returns (uint256) {
        return collateral.balanceOf(address(this));
    }

    function queuedAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
