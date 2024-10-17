// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {IVault as ISymVault} from "src/interfaces/symbiotic/IVault.sol";

/**
 * @title SymbioticDelegator
 * @dev Delegator contract for wStETH on Symbiotic
 */
contract SymbioticDelegatorV2 is Initializable, AffineDelegator, AffineGovernable {
    uint256 public constant MAX_PENDING_EPOCHS = 50;

    // index starting with 1 to avoid confusion with zero in mapping
    uint256[MAX_PENDING_EPOCHS + 1] public pendingEpochs;
    uint256 public pendingEpochCount;
    mapping(uint256 => uint256) public pendingEpochIndex;

    ISymVault symVault;

    /**
     * @dev Initialize the contract
     * @param _vault Vault address
     * @param _symVault SymVault address
     */
    function initialize(address _vault, address _symVault) external initializer {
        governance = UltraLRT(_vault).governance();
        asset = ERC20(UltraLRT(_vault).asset());

        vault = _vault;
        symVault = ISymVault(_symVault);

        require(symVault.collateral() == address(asset), "SymbioticDelegator: Invalid collateral");
    }

    function _delegate(uint256 amount) internal override {
        asset.approve(address(symVault), amount);
        symVault.deposit(address(this), amount);
    }

    function _requestWithdrawal(uint256 assets) internal override {
        uint256 epoch = symVault.currentEpoch() + 1;

        symVault.withdraw(address(this), assets);

        if (pendingEpochIndex[epoch] == 0) {
            pendingEpochCount++;
            pendingEpochs[pendingEpochCount] = epoch;
            pendingEpochIndex[epoch] = pendingEpochCount;
        }
    }

    function _isValidEpoch(uint256 epoch) internal view {
        require(symVault.isWithdrawalsClaimed(epoch, address(this)) == false, "SymbioticDelegator: Withdrawal claimed");

        require(symVault.withdrawalsOf(epoch, address(this)) == 0, "SymbioticDelegator: Withdrawal not completed");
    }

    function completeWithdrawalRequest(uint256 epoch) external onlyHarvester {
        require(pendingEpochIndex[epoch] != 0, "SymbioticDelegator: No pending withdrawal request for the epoch");

        require(epoch < symVault.currentEpoch(), "SymbioticDelegator: Epoch is not completed");

        _isValidEpoch(epoch);

        uint256 index = pendingEpochIndex[epoch];
        uint256 lastEpoch = pendingEpochs[pendingEpochCount];

        symVault.claim(address(this), epoch);

        if (index != pendingEpochCount) {
            pendingEpochs[index] = lastEpoch;
            pendingEpochIndex[lastEpoch] = index;
        }

        pendingEpochIndex[epoch] = 0;
        pendingEpochs[pendingEpochCount] = 0;
        pendingEpochCount--;
    }

    function addExternalEpoch(uint256 epoch) external onlyHarvester {
        require(pendingEpochIndex[epoch] == 0, "SymbioticDelegator: Epoch already pending");

        require(epoch <= (symVault.currentEpoch() + 1), "SymbioticDelegator: Epoch is not active");

        _isValidEpoch(epoch);

        require(pendingEpochCount < MAX_PENDING_EPOCHS, "SymbioticDelegator: Too many pending epochs");

        pendingEpochCount++;
        pendingEpochs[pendingEpochCount] = epoch;
        pendingEpochIndex[epoch] = pendingEpochCount;
    }

    /**
     * @notice Get withdrawable assets
     * @return Amount of withdrawable assets
     */
    function withdrawableAssets() public view override returns (uint256) {
        return symVault.activeBalanceOf(address(this));
    }

    /**
     * @notice Get queued assets
     * @return Amount of queued assets
     */
    function queuedAssets() public view override returns (uint256) {
        uint256 total = asset.balanceOf(address(this));
        for (uint256 i = 1; i <= pendingEpochCount; i++) {
            total += symVault.withdrawalsOf(pendingEpochs[i], address(this));
        }
        return total;
    }
}
