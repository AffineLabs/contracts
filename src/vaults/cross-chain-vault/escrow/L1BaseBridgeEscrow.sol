//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";

import {IRootChainManager} from "src/interfaces/IRootChainManager.sol";
import {BridgeEscrow} from "./BridgeEscrow.sol";
import {L1Vault} from "src/vaults/cross-chain-vault/L1Vault.sol";
import {LevEthL1} from "src/strategies/LevEthL1.sol";

interface IBaseBridge {
        function depositTransaction(
            address _to,
            uint256 _value,
            uint64 _gasLimit,
            bool _isCreation,
            bytes calldata _data
        ) external payable;
    }

contract L1BridgeEscrow is BridgeEscrow {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;

    /// @notice The L1Vault.
    L1Vault public immutable vault;
    /// @notice Polygon Pos Bridge manager. See https://github.com/maticnetwork/pos-portal/blob/41d45f7eff5b298941a2547afa0073a6c36b2b9c/contracts/root/RootChainManager/RootChainManager.sol
    IRootChainManager public immutable rootChainManager;
    IBaseBridge public baseBridge;
    LevEthL1 public strategy;

    event TransferToStrategy(uint256 assets);

    IWETH public constant WETH = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    constructor(L1Vault _vault, IRootChainManager _manager, address _baseBridge) BridgeEscrow(_vault) {
        vault = _vault;
        rootChainManager = _manager;
        baseBridge = IBaseBridge(_baseBridge);
    }

    function setStrategy(LevEthL1 _strategy) external onlyGovernance {
        strategy = _strategy;
    }


    function bridge(
        address _recipient,
        uint256 _amount
    ) external payable {
        require(msg.value > 0, "Must send ETH");
        require(_amount == msg.value, "Value and amount need to be the same");

        baseBridge.depositTransaction{value: msg.value}(
            _recipient,
            _amount,
            100000,
            false,
            "0x01",
            type(uint256).max
        );
        wormholeRouter.reportFundTransfer(_amount);
    }

    function _clear(uint256 assets, bytes calldata exitProof) internal override {
         // Exit tokens, after this the withdrawn tokens from L2 will be reflected in the L1 BridgeEscrow
        // NOTE: This function can fail if the exitProof provided is fake or has already been processed
        // In either case, we want to send at least `assets` to the vault since we know that the L2Vault sent `assets`
        try rootChainManager.exit(exitProof) {} catch {}

        uint256 contractBalance = address(this).balance;
        require(contractBalance >= assets, "BE: Funds not received");
        
        // Wrap recieved eth

        uint256 amountToWrap = Math.min(assets, contractBalance);
        WETH.deposit{value: amountToWrap}();
        
        uint256 balance = asset.balanceOf(address(this));

        asset.safeTransfer(address(strategy), balance);
        emit TransferToStrategy(balance);


        // call afterReceive on strat to reset canRequest
        strategy.afterReceive();
    }
}
