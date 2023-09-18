// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Vault, MathUpgradeable, Math, SafeTransferLib, ERC20} from "src/vaults/Vault.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

/// @notice The same as Vault, but ONLY raw ether can be withdrawn.
contract EthVault is Vault {
    using SafeTransferLib for ERC20;

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _liquidate(assets);

        // Slippage during liquidation means we might get less than `assets` amount of `_asset`
        assets = Math.min(_asset.balanceOf(address(this)), assets);
        uint256 assetsFee = _getWithdrawalFee(assets, owner);
        uint256 assetsToUser = assets - assetsFee;

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);

        // Convert WETH to ETH and send to user
        IWETH(address(_asset)).withdraw(assetsToUser);
        (bool success,) = receiver.call{value: assetsToUser}("");
        require(success, "EthVault: ETH transfer failed");
        // Send withdrawal fee to governance
        _asset.safeTransfer(governance, assetsFee);
    }
}
