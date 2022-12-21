// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "../BaseVault.sol";
import {IRootChainManager} from "../interfaces/IRootChainManager.sol";
import {L1BridgeEscrow} from "./L1BridgeEscrow.sol";
import {L1WormholeRouter} from "./L1WormholeRouter.sol";

contract L1Vault is PausableUpgradeable, UUPSUpgradeable, BaseVault {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION/UPGRADING
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the vault.
    function initialize(
        address _governance,
        ERC20 _token,
        address _wormholeRouter,
        L1BridgeEscrow _bridgeEscrow,
        IRootChainManager _chainManager,
        address _predicate
    ) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        baseInitialize(_governance, _token, _wormholeRouter, _bridgeEscrow);
        chainManager = _chainManager;
        predicate = _predicate;
    }

    /// @notice See `UUPSUpgradeable`. Only the gov address can do an upgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN REBALANCING
    //////////////////////////////////////////////////////////////*/

    /// @notice True if this vault has received latest transfer from L2, else false.
    bool public received;

    /// @notice The contract that manages transfers to L2. We'll call `depositFor` on this.
    IRootChainManager public chainManager;

    /**
     * @notice The address that will actually take `asset` from the vault.
     * @dev Make sure to call approve the predicate as a spender before calling `depositFor`.
     * More can be found here: https://github.com/maticnetwork/pos-portal/blob/88dbf0a88fd68fa11f7a3b9d36629930f6b93a05/contracts/root/RootChainManager/RootChainManager.sol#L267
     */
    address public predicate;

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
        _liquidate(amountRequested);
        uint256 amountToSend = Math.min(_asset.balanceOf(address(this)), amountRequested);
        _asset.safeApprove(predicate, amountToSend);
        chainManager.depositFor(address(bridgeEscrow), address(_asset), abi.encodePacked(amountToSend));

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

    /// @notice Called by the bridgeEscrow after it transfers `asset` into this vault.
    function afterReceive() external {
        require(msg.sender == address(bridgeEscrow), "L1: only escrow");
        received = true;
        // Whenever we receive funds from L2, immediately deposit them all into strategies
        _depositIntoStrategies(_asset.balanceOf(address(this)));
    }

    /// @dev The L1Vault's profit does not need to unlock over time, because users to do not transact with it
    function lockedProfit() public pure override returns (uint256) {
        return 0;
    }
}
