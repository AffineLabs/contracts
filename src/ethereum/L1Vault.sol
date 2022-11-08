// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {BaseVault} from "../BaseVault.sol";
import {IRootChainManager} from "../interfaces/IRootChainManager.sol";
import {L1BridgeEscrow} from "./L1BridgeEscrow.sol";
import {L1WormholeRouter} from "./L1WormholeRouter.sol";

contract L1Vault is PausableUpgradeable, UUPSUpgradeable, BaseVault {
    using SafeTransferLib for ERC20;

    /////// Cross chain rebalancing
    bool public received;
    IRootChainManager public chainManager;
    // `predicate` will take tokens from vault when depositFor is called on the RootChainManager
    // solhint-disable-next-line max-line-length
    // https://github.com/maticnetwork/pos-portal/blob/88dbf0a88fd68fa11f7a3b9d36629930f6b93a05/contracts/root/RootChainManager/RootChainManager.sol#L267
    address public predicate;

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

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @dev The L1Vault's profit does not need to unlock over time, because users to do not transact with it
    function lockedProfit() public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Emitted whenever we send our tvl to l2
     * @param tvl The current tvl of this vault.
     */
    event SendTVL(uint256 tvl);

    function sendTVL() external {
        uint256 tvl = vaultTVL();

        // Report TVL to L2.
        L1WormholeRouter(wormholeRouter).reportTVL(tvl, received);

        // If received == true then the l2-l1 bridge gets unlocked upon message reception in l2
        // Resetting this to false since we haven't received any new transfers from L2 yet
        if (received) {
            received = false;
        }
        emit SendTVL(tvl);
    }

    // Process a request for funds from L2 vault
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

    function afterReceive() external {
        require(msg.sender == address(bridgeEscrow), "L1: only escrow");
        received = true;
        // Whenever we receive funds from L1, immediately deposit them all into strategies
        _depositIntoStrategies();
    }
}
