//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BridgeEscrow} from "../BridgeEscrow.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";

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

contract L2BridgeEscrowBase is BridgeEscrow {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;

    /// @notice The L2Vault.
    L2Vault public vault;

    IAcrossBridge public acrossBridge = IAcrossBridge(payable(0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64));
    address public l1EscrowAddress;
    IWETH public constant WETH = IWETH(payable(0x4200000000000000000000000000000000000006));

    constructor(L2Vault _vault) BridgeEscrow(_vault) {
        vault = _vault;
        asset.safeApprove(address(acrossBridge), type(uint256).max);
    }

    fallback() external payable {}
    
    receive() external payable {}

    function setVault(address _vaultAddress) external {
        require(msg.sender == governance, "BE: Only Governance");
        vault = L2Vault(_vaultAddress);
    }

    // function to withdraw eth from the contract
    function withdrawEth(uint256 _amount) external {
        require(msg.sender == governance, "BE: Only Governance");
        payable(governance).transfer(_amount);
    }

    // function to withdraw tokens from the contract
    function withdrawToken(address _token, uint256 _amount) external {
        require(msg.sender == governance, "BE: Only Governance");
        ERC20(_token).safeTransfer(governance, _amount);
    }

    function setAcrossBridge(address _acrossBridgeAddress) external {
        require(msg.sender == governance, "BE: Only Governance");
        acrossBridge = IAcrossBridge(_acrossBridgeAddress);
    }

    function setL1Escrow(address _l1EscrowAddress) external {
        require(msg.sender == governance, "BE: Only Governance");
        l1EscrowAddress = _l1EscrowAddress;
    }

    function bridgeToL1(
        uint256 _amount,
        int64 _relayerFeePct
    ) external {
        require(msg.sender == governance, "BE: Only Gov");

        // Unwrap WETH
        uint256 wethBalance = asset.balanceOf(address(this));
        uint256 amountToWithdraw = Math.min(_amount, wethBalance);

        bytes4 depositSelector = bytes4(keccak256("deposit(address,address,uint256,uint256,int64,uint32,bytes,uint256)"));

        // Encode parameters
        bytes memory encodedParameters = abi.encodeWithSelector(
            depositSelector,
            l1EscrowAddress,
            address(WETH),
            amountToWithdraw,
            1,
            _relayerFeePct,
            uint32(acrossBridge.getCurrentTime()),
            "",
            type(uint256).max
        );

        bytes memory delimiterAndReferrer = abi.encodePacked(
            hex"d00dfeeddeadbeef",
            governance  
        );

        // Final calldata
        bytes memory finalCalldata = abi.encodePacked(encodedParameters, delimiterAndReferrer);

        (bool success, ) = address(acrossBridge).call(finalCalldata);
        require(success, "Escrow: Bridge call failed"); 
    }

    function _clear(uint256 amount, bytes calldata /* exitProof */ ) internal override {
        // Wrap any recieved eth
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
        uint256 balance = asset.balanceOf(address(this));
        // require(balance >= amount, "BE: Funds not received");
        uint256 amountToSend = Math.min(balance, amount);
        asset.safeTransfer(address(vault), amountToSend);

        emit TransferToVault(balance);
        vault.afterReceive(balance);
    }
}