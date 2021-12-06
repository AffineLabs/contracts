//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import { L1Vault } from "./eth-contracts/L1Vault.sol"; 
import { L2Vault } from "./polygon-contracts/L2Vault.sol"; 
import { ContractRegistry } from "./ContractRegistry.sol";

interface IERC20 {
    function withdraw(uint256 amount) external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

interface IRootChainManager {
    function exit(bytes memory _data) external;
}

contract Staging {
    ContractRegistry public l1ContractRegistry;
    ContractRegistry public l2ContractRegistry;
    uint24 public rootChainId;
    uint24 public childChainId;

    constructor(
        address _l1ContractRegistryAddress,
        address _l2ContractRegistryAddress,
        uint24 _rootChainId,
        uint24 _childChainId
    ) {
        l1ContractRegistry = ContractRegistry(_l1ContractRegistryAddress);
        l2ContractRegistry = ContractRegistry(_l2ContractRegistryAddress);
        rootChainId = _rootChainId;
        childChainId = _childChainId;
    }

    modifier onlyRootChain() {
        require(block.chainid == rootChainId, "ONLY_ROOT");
        _;
    }

    modifier onlyChildChain() {
        require(block.chainid == childChainId, "ONLY_CHILD");
        _;
    }

    function l2Withdraw(uint256 amount) external onlyChildChain {
        require(msg.sender == l2ContractRegistry.getAddress("L2Vault"), "Staging[l2Withdraw]: Only L2 vault should be able to withdraw funds.");
        IERC20(l2ContractRegistry.getAddress("L2USDC")).withdraw(amount);
    }
    
    function l2ClearFund(uint256 lastL1TransferBlockNum, uint256 lastL1TransferAmount) external onlyChildChain {
        require(msg.sender == l2ContractRegistry.getAddress("Defender"), "Staging[l2ClearFund]: Only defender should be able to clear fund in L2.");
        L2Vault(l2ContractRegistry.getAddress("L2Vault")).stagingClearFundCallback(lastL1TransferBlockNum);
        IERC20(l2ContractRegistry.getAddress("L2USDC")).transfer(l2ContractRegistry.getAddress("L2Vault"), lastL1TransferAmount);
    }

    function l1Exit(uint256 lastL2TransferBlockNum, uint256 lastL2TransferAmount, bytes calldata data) external onlyRootChain {
        require(msg.sender == l1ContractRegistry.getAddress("Defender"), "Staging[l1Exit]: Only defender should be able to exit in L1.");
        L1Vault(l1ContractRegistry.getAddress("L1Vault")).stagingClearFundCallback(lastL2TransferBlockNum);
        // Exit tokens, after that the withdrawn tokens in L2 will be reflected in this smart contract.
        IRootChainManager(l1ContractRegistry.getAddress("L1ChainManager")).exit(data);
        // Transfer exited tokens to L1 Vault.
        IERC20(l1ContractRegistry.getAddress("L1USDC")).transfer(l1ContractRegistry.getAddress("L1Vault"), lastL2TransferAmount);
    }
}