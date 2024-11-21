//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";

import {BridgeEscrow} from "./BridgeEscrow.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {L2WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/L2WormholeRouter.sol";
import {LevEthL2} from "src/strategies/LevEthL2.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external;
}

interface IAcrossBridge {
     function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        int64 relayerFeePct,
        uint32 quoteTimestamp,
        bytes calldata message,
        uint256 maxCount
    ) external payable;

    function speedUpDeposit(
        address deoisitor,
        int64 updatedRelayerFeePct,
        uint32 depositId,
        address updatedRecipient,
        bytes calldata updatedMessage,
        bytes calldata depositorSignature
    ) external payable;

    function getCurrentTime() external view returns (uint256);

    function depositQuoteTimeBuffer() external view returns (uint32);
}

contract L2BaseBridgeEscrow is BridgeEscrow {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;
    
    IAcrossBridge public acrossBridge;
    L2WormholeRouter public wormholeRouter;
    IWETH public constant WETH = IWETH(0x4200000000000000000000000000000000000006);
    LevEthL2 public strategy;

    /// @notice The L2Vault.
    L2Vault public immutable vault;
    
    constructor(L2Vault _vault, address _acrossBridgeAddress, address _wormholeRouter) BridgeEscrow(_vault) {
        vault = _vault;
        acrossBridge = IAcrossBridge(_acrossBridgeAddress);
        wormholeRouter = L2WormholeRouter(_wormholeRouter);
    }

    function setStrategy(LevEthL2 _strategy) external onlyGovernance {
        strategy = _strategy;
    }

    function bridge(
        address _recipient,
        uint256 _amount,
        int64 _relayerFeePct
    ) external payable {
        require(msg.value > 0, "Must send ETH");
        require(_amount == msg.value, "Value and amount need to be the same");

        acrossBridge.deposit{value: msg.value}(
            _recipient,
            address(WETH),
            _amount,
            1, // bridge to ethereum
            _relayerFeePct,
            uint32(acrossBridge.getCurrentTime()),
            "",
            type(uint256).max
        );
        wormholeRouter.reportFundTransfer(_amount);
    }

    function speedUpBridge(
        int64 _updatedRelayerFeePct,
        uint32 _depositId,
        address _updatedRecipient,
        bytes calldata _updatedMessage,
        bytes calldata _depositorSignature
    ) external payable {
        require(msg.value > 0, "Must send ETH");

        acrossBridge.speedUpDeposit{value: msg.value}(
            msg.sender,
            _updatedRelayerFeePct,
            _depositId,
            _updatedRecipient,
            _updatedMessage,
            _depositorSignature
        );
    }

   event TransferToStrategy(uint256 assets);

    function _clear(uint256 assets, bytes calldata exitProof) internal override {
        // Exit tokens, after this the withdrawn tokens from L2 will be reflected in the L1 BridgeEscrow
        // NOTE: This function can fail if the exitProof provided is fake or has already been processed
        // In either case, we want to send at least `assets` to the vault since we know that the L2Vault sent `assets`
        try rootChainManager.exit(exitProof) {} catch {}

        // Transfer exited tokens to L1 Vault.
        uint256 balance = asset.balanceOf(address(this));
        require(balance >= assets, "BE: Funds not received");

        asset.safeTransfer(address(strategy), balance);
        emit TransferToStrategy(balance);

        // call afterReceive on strat to reset canRequest
        strategy.afterReceive();
    }
}
