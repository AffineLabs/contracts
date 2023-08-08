// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {VaultV2, MathUpgradeable, SafeTransferLib, ERC20} from "src/vaults/VaultV2.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

/// @notice The same as Vault, but ONLY raw ether can be withdrawn.
contract EthVaultV2 is VaultV2 {
    using SafeTransferLib for ERC20;

    /// @dev We need this to receive ETH when calling WETH.withdraw()
    receive() external payable {}

    function weth() public pure virtual returns (IWETH) {
        return IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _liquidate(assets);

        // Slippage during liquidation means we might get less than `assets` amount of `_asset`
        assets = MathUpgradeable.min(_asset.balanceOf(address(this)), assets);
        uint256 assetsFee = _getWithdrawalFee(assets, owner);
        uint256 assetsToUser = assets - assetsFee;

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);

        // Convert WETH to ETH and send to user
        weth().withdraw(assetsToUser);
        (bool success,) = receiver.call{value: assetsToUser}("");
        require(success, "EthVault: ETH transfer failed");
        // Send withdrawal fee to governance
        _asset.safeTransfer(governance, assetsFee);
    }
}
