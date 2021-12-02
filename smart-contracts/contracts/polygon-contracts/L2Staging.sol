
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { L2Vault } from './L2Vault.sol';
import { ContractRegistry } from '../ContractRegistry.sol';

contract L2Staging {
    // Last cleared L1 block number when L1 last sent liquidity to L2.
    uint256 public lastClearedL1TransferBlockNum;
    // Address of L2 contarct registry.
    ContractRegistry public l2ContractRegistry;

    constructor(address _l2ContractRegistryAddress) {
        l2ContractRegistry = ContractRegistry(_l2ContractRegistryAddress);
    }

    function clearFund(uint256 lastL1TransferBlockNum, uint256 lastL1TransferAmount) public {
        require(msg.sender == l2ContractRegistry.getAddress("Defender"), "L2Staging[setNewL1TransferDataAndClear]: Only defender should be able to clear fund.");
        require(lastL1TransferBlockNum != lastClearedL1TransferBlockNum, "This transfer has already been cleared.");
        lastClearedL1TransferBlockNum = lastL1TransferBlockNum;
        address uscdAddress = l2ContractRegistry.getAddress("L2USDC");
        IERC20(uscdAddress).transfer(l2ContractRegistry.getAddress("L2Vault"), lastL1TransferAmount);
    }
}