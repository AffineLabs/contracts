// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ContractRegistry } from '../ContractRegistry.sol';
import { Staging } from "../Staging.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 value) external returns (bool);
}

abstract contract L2BalancableVault {
    // L2 block number when L2 last sent liquidity to L1.
    uint256 public lastTransferBlockNum;
    // Amount (in USDC) that L2 last sent to L1 as liquidity.
    uint256 public lastTransferAmount;
    // Last cleared L2 block number when L2 last sent liquidity to L1.
    uint256 public lastClearedTransferBlockNum;
    // Address of L2 contarct registry.
    ContractRegistry public l2ContractRegistry;
    // Last cleared L1 block number when L1 last sent liquidity to L2.
    uint256 public lastClearedL1TransferBlockNum;

    constructor(address _l2ContractRegistryAddress) {
        l2ContractRegistry = ContractRegistry(_l2ContractRegistryAddress);
    }

    // This is currently set by defender bot when it observes that some fund has been cleared in L1 staging contract.
    function setlastClearedTransferBlockNum(uint256 _lastClearedTransferBlockNum) external {
        require(msg.sender == l2ContractRegistry.getAddress("Defender"), "L2BalancableVault[setlastClearedTransferBlockNum]: Only defender should be able to set last cleared Transfer block number.");
        lastClearedTransferBlockNum = _lastClearedTransferBlockNum;
    }

    function stagingClearFundCallback(uint256 lastL1TransferBlockNum) external {
        require(msg.sender == l2ContractRegistry.getAddress("L2Staging"), "L2BalancableVault[stagingClearFundCallback]: Only L2 staging should be able call clear fund callback.");
        require(lastL1TransferBlockNum != lastClearedL1TransferBlockNum, "This transfer has already been cleared.");
        lastClearedL1TransferBlockNum = lastL1TransferBlockNum;
    }

    function _transferFundsToL1(uint256 amount) internal {
        // Check if the bridge is locked or not.
        require(lastClearedTransferBlockNum == lastTransferBlockNum, "L2BalancableVault[transferFundsToL2]: Last transfer hasn't been cleared yet.");
        lastTransferBlockNum = block.number;
        lastTransferAmount = amount;
        address l2Staging = l2ContractRegistry.getAddress("L2Staging");
        IChildERC20(l2ContractRegistry.getAddress("L2USDC")).transfer(l2ContractRegistry.getAddress("L2Staging"), amount);
        Staging(l2Staging).l2Withdraw(amount);
    }    
}