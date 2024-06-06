// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";

import {
    WithdrawalInfo,
    QueuedWithdrawalParams,
    ApproverSignatureAndExpiryParams,
    IDelegationManager,
    IStrategyManager,
    IStrategy
} from "src/interfaces/eigenlayer/eigen.sol";

/**
 * @title AffineDelegator
 * @dev Delegator contract for stETH on Eigenlayer
 */
abstract contract AffineDelegator {
    using SafeTransferLib for ERC20;

    UltraLRT public vault;
    ERC20 public asset;

    modifier onlyVaultOrHarvester() {
        require(
            vault.hasRole(vault.HARVESTER(), msg.sender) || msg.sender == address(vault),
            "AffineDelegator: Not a vault or harvester"
        );
        _;
    }

    /**
     * @dev Delegate & restake stETH to operator on Eigenlayer
     */
    function delegate(uint256 amount) external onlyVaultOrHarvester {
        asset.transferFrom(address(vault), address(this), amount);
        _delegate(amount);
    }

    function _delegate(uint256 amount) internal virtual {}

    /**
     * @dev Request withdrawal from eigenlayer
     */
    function requestWithdrawal(uint256 assets) external onlyVaultOrHarvester {
        _requestWithdrawal(assets);
    }

    function _requestWithdrawal(uint256 assets) internal virtual {}

    /**
     * @dev Withdraw stETH from delegator to vault
     */
    function withdraw() external virtual onlyVaultOrHarvester {
        asset.safeTransfer(address(vault), asset.balanceOf(address(this)));
    }

    // view functions
    function totalLockedValue() public view returns (uint256) {
        return withdrawableAssets() + queuedAssets();
    }

    function withdrawableAssets() public view virtual returns (uint256) {}

    function queuedAssets() public view virtual returns (uint256) {}
}
