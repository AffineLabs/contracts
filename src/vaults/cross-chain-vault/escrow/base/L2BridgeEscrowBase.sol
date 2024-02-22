//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BridgeEscrow} from "../BridgeEscrow.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {IAcrossBridge} from "src/interfaces/IAcrossBridge.sol";


contract L2BridgeEscrowBase is BridgeEscrow {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;

    /// @notice The L2Vault.
    L2Vault public vault;

    IAcrossBridge public acrossBridge;
    address public l1EscrowAddress;
    IWETH public constant WETH = IWETH(payable(0x4200000000000000000000000000000000000006));

    constructor(L2Vault _vault) BridgeEscrow(_vault) {
        vault = _vault;
        asset.safeApprove(address(acrossBridge), type(uint256).max);
        acrossBridge = IAcrossBridge(payable(0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64));
    }

    fallback() external payable {}
    
    receive() external payable {}

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only Governance.");
        _;
    }

    // function to withdraw eth from the contract
    function withdrawEth(uint256 _amount) external onlyGovernance {
        payable(governance).transfer(_amount);
    }

    // function to withdraw tokens from the contract
    function withdrawToken(address _token, uint256 _amount) external onlyGovernance {
        ERC20(_token).safeTransfer(governance, _amount);
    }

    function setAcrossBridge(address _acrossBridgeAddress) external onlyGovernance {
        acrossBridge = IAcrossBridge(_acrossBridgeAddress);
    }

    function setL1Escrow(address _l1EscrowAddress) external onlyGovernance{
        l1EscrowAddress = _l1EscrowAddress;
    }

    function bridgeToL1(
        uint256 _amount,
        int64 _relayerFeePct
    ) external {
        require(msg.sender == address(vault), "BE: Only vault");

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