// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {IRootChainManager} from "../interfaces/IRootChainManager.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {BaseVault} from "../BaseVault.sol";
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

    constructor() {}

    function initialize(
        address _governance,
        ERC20 _token,
        address _wormholeRouter,
        BridgeEscrow _bridgeEscrow,
        IRootChainManager _chainManager,
        address _predicate
    ) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        BaseVault.baseInitialize(_governance, _token, _wormholeRouter, _bridgeEscrow);
        chainManager = _chainManager;
        predicate = _predicate;
    }

    function _msgSender() internal view override (Context, ContextUpgradeable) returns (address) {
        return Context._msgSender();
    }

    function _msgData() internal view override (Context, ContextUpgradeable) returns (bytes calldata) {
        return Context._msgData();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @dev The L1Vault's profit does not need to unlock over time, because users to do not transact with it
    function lockedProfit() public pure override returns (uint256) {
        return 0;
    }

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
        require(msg.sender == address(wormholeRouter), "Only wormhole router");
        _liquidate(amountRequested);
        uint256 amountToSend = Math.min(_asset.balanceOf(address(this)), amountRequested);
        _transferFundsToL2(amountToSend);
    }

    event FundTransferToL2(uint256 amount);

    // Send `asset` to L2 BridgeEscrow via polygon bridge
    function _transferFundsToL2(uint256 amount) internal {
        _asset.safeApprove(predicate, amount);
        chainManager.depositFor(address(bridgeEscrow), address(_asset), abi.encodePacked(amount));

        // Let L2 know how much money we sent
        L1WormholeRouter(wormholeRouter).reportTransferredFund(amount);
        emit FundTransferToL2(amount);
    }

    function afterReceive() external {
        require(msg.sender == address(bridgeEscrow), "Only L1 BridgeEscrow.");
        received = true;
        // Whenever we receive funds from L1, immediately deposit them all into strategies
        _depositIntoStrategies();
    }
}
