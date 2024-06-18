// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

interface IUltraLRT {
    function hasRole(bytes32 role, address user) external view returns (bool);
    function HARVESTER() external view returns (bytes32);
}

/**
 * @title AffineDelegator
 * @dev Delegator contract for stETH on Eigenlayer
 */
abstract contract AffineDelegator {
    using SafeTransferLib for ERC20;

    address public vault;
    ERC20 public asset;
    /**
     * @notice Modifier to allow function calls only from the vault or harvester
     */

    modifier onlyVaultOrHarvester() {
        require(
            IUltraLRT(vault).hasRole(IUltraLRT(vault).HARVESTER(), msg.sender) || msg.sender == vault,
            "AffineDelegator: Not a vault or harvester"
        );
        _;
    }

    /**
     * @dev Delegate & restake stETH to operator
     */
    function delegate(uint256 amount) external onlyVaultOrHarvester {
        asset.transferFrom(address(vault), address(this), amount);
        _delegate(amount);
    }

    /**
     * @dev Delegate stETH to operator
     */
    function _delegate(uint256 amount) internal virtual {}

    /**
     * @notice Request withdrawal from eigenlayer
     * @param assets Amount to withdraw
     * @dev Request withdrawal from eigenlayer
     */
    function requestWithdrawal(uint256 assets) external onlyVaultOrHarvester {
        _requestWithdrawal(assets);
    }

    /**
     * @dev Request withdrawal from eigenlayer
     */
    function _requestWithdrawal(uint256 assets) internal virtual {}

    /**
     * @dev Withdraw stETH from delegator to vault
     */
    function withdraw() external virtual onlyVaultOrHarvester {
        asset.safeTransfer(vault, asset.balanceOf(address(this)));
    }

    /**
     * @notice Get total locked value
     * @return Total locked value
     */
    function totalLockedValue() public view virtual returns (uint256) {
        return withdrawableAssets() + queuedAssets();
    }

    /**
     * @notice Get withdrawable assets
     * @return Amount of withdrawable assets
     */
    function withdrawableAssets() public view virtual returns (uint256) {}

    /**
     * @notice Get queued assets
     * @return Amount of queued assets
     */
    function queuedAssets() public view virtual returns (uint256) {}
}
