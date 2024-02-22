//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BridgeEscrow} from "../BridgeEscrow.sol";
import {L1Vault} from "src/vaults/cross-chain-vault/L1Vault.sol";
import {IBaseBridge} from "src/interfaces/IBaseBridge.sol";



contract L1BridgeEscrowBase is BridgeEscrow {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;

    /// @notice The L1Vault.
    L1Vault public immutable vault;

    IBaseBridge public baseBridge;
    uint64 constant BASE_GAS_LIMIT = 100000;
    // IBaseBridge public baseBridge = IBaseBridge(payable(0x49f53e41452C74589E85cA1677426Ba426459e85)); // testnet
    address public l2EscrowAddress;
    IWETH public constant WETH = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)); //mainnet
    // IWETH public constant WETH = IWETH(payable(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9)); //testnet

    // uint256 public maxAcrossFeePct = 1000;

    constructor(L1Vault _vault) BridgeEscrow(_vault) {
        vault = _vault;
        baseBridge = IBaseBridge(payable(0x49048044D57e1C92A77f79988d21Fa8fAF74E97e)); // mainnet
    }

    fallback() external payable {}
    
    receive() external payable {}

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only Governance.");
        _;
    }

    function setL2Escrow(address _l2EscrowAddress) external onlyGovernance {
        l2EscrowAddress = _l2EscrowAddress;
    }

    function bridgeToL2(
        uint256 _amount
    ) external payable{
        require(_amount > 0, "Must send ETH");
        require(msg.sender == address(vault), "BE: Only vault");

        // unwrap weth
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 amountToUnwrap = Math.min(wethBalance, _amount);
        WETH.withdraw(amountToUnwrap);

        uint256 balance = address(this).balance;
        uint256 amountToBridge = Math.min(balance, _amount);
        
        baseBridge.depositTransaction{value: amountToBridge}(
            l2EscrowAddress,
            amountToBridge,
            BASE_GAS_LIMIT,
            false,
            "0x01"
        );
    }

    // function to withdraw eth from the contract
    function withdrawEth(uint256 _amount) external onlyGovernance{
        payable(governance).transfer(_amount);
    }

    // function to withdraw tokens from the contract
    function withdrawToken(address _token, uint256 _amount) external onlyGovernance {
        ERC20(_token).safeTransfer(governance, _amount);
    }

    function _clear(uint256 assets, bytes calldata /* exitProof */ ) internal override {
        // get balance of native eth
        // uint256 balance = address(this).balance;
        // Wrap any recieved eth
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }

        uint256 balance = asset.balanceOf(address(this));

        uint256 amountToSend = Math.min(balance, assets);
        asset.safeTransfer(address(vault), amountToSend);

        emit TransferToVault(amountToSend);
        vault.afterReceive();
    }
}
