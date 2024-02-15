// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVaultV2} from "src/vaults/cross-chain-vault/BaseVaultV2.sol";
import {L1BridgeEscrowBase} from "src/vaults/cross-chain-vault/escrow/base/L1BridgeEscrowBase.sol";
import {L1WormholeRouter} from "../wormhole/L1WormholeRouter.sol";
import {Vault} from "src/vaults/Vault.sol";

contract L1VaultBase is PausableUpgradeable, UUPSUpgradeable, BaseVaultV2 {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION/UPGRADING
    //////////////////////////////////////////////////////////////*/
    Vault public parentVault;


    /// @notice Initialize the vault.
    function initialize(
        address _governance,
        ERC20 _token,
        address _wormholeRouter,
        L1BridgeEscrowBase _bridgeEscrow,
        address _parentVault
    ) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        baseInitialize(_governance, _token, _wormholeRouter, _bridgeEscrow);
        parentVault = Vault(_parentVault);
        _asset.safeApprove(address(parentVault), type(uint256).max);
    }


    /// @notice See `UUPSUpgradeable`. Only the gov address can do an upgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN REBALANCING
    //////////////////////////////////////////////////////////////*/

    /// @notice True if this vault has received latest transfer from L2, else false.
    bool public received;

    /**
     * @notice Emitted whenever we send our tvl to l2
     * @param tvl The current tvl of this vault.
     */
    event SendTVL(uint256 tvl);

    /// @notice Send this vault's tvl to the L2Vault
    function sendTVL() external {
        uint256 tvl = vaultTVL();

        // Report TVL to L2. Also possibly unlock L2-L1 bridge (if received is true)
        L1WormholeRouter(wormholeRouter).reportTVL(tvl, received);

        // If `received` is true, then an L2-L1 cross-chain transfer has completed.
        // Sending this tvl might trigger another L2-L1 transfer.
        // Reset `received` to false so that L2-L1 bridge will remain locked.
        // See L2Vault.sol for more on how `received` is used.
        if (received) {
            received = false;
        }
        emit SendTVL(tvl);
    }

    /**
     * @notice Process a request for funds from L2 vault
     * @param amountRequested The amount requested.
     */
    function processFundRequest(uint256 amountRequested) external {
        require(msg.sender == address(wormholeRouter), "L1: only router");
        uint256 currBalance = _asset.balanceOf(address(this));
        if(currBalance<amountRequested){
            uint256 amountToLiquidate = amountRequested - currBalance;
            totalStrategyHoldings -= amountToLiquidate;
            parentVault.withdraw(amountToLiquidate, address(this), address(this)); 
        }

        // sell amount requested
        uint256 amountToSend = Math.min(_asset.balanceOf(address(this)), amountRequested);
        _asset.safeTransfer(address(bridgeEscrow), amountToSend);

        L1BridgeEscrowBase(payable(address(bridgeEscrow))).bridgeToL2(
            amountToSend
        );

        // Let L2 know how much money we sent
        L1WormholeRouter(wormholeRouter).reportFundTransfer(amountToSend);
        emit TransferToL2({assetsRequested: amountRequested, assetsSent: amountToSend});
    }

    /**
     * @notice Emitted whenever we send assets to L2.
     * @param assetsRequested The assets requested by L2.
     * @param assetsSent The assets we actually sent.
     */
    event TransferToL2(uint256 assetsRequested, uint256 assetsSent);

    // function to withdraw eth from the contract
    function withdrawEth(uint256 _amount) external onlyGovernance{
        payable(governance).transfer(_amount);
    }

    // function to withdraw tokens from the contract
    function withdrawToken(address _token, uint256 _amount) external onlyGovernance{
        ERC20(_token).safeTransfer(governance, _amount);
    }

    function setParentVault(address _parentVault) external onlyGovernance {
        parentVault = Vault(_parentVault);
        _asset.safeApprove(address(parentVault), type(uint256).max);
    }

    /// @notice Called by the bridgeEscrow after it transfers `asset` into this vault.
    function afterReceive() external {
        require(msg.sender == address(bridgeEscrow), "L1: only escrow"); 
        received = true;
        // Whenever we receive funds from L2, immediately buy parent vault and increase totalStrategyHoldings
        uint256 balance = _asset.balanceOf(address(this));
        totalStrategyHoldings += balance;
        parentVault.deposit(balance, address(this));
    }
}
