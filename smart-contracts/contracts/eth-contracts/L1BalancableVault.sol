// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseVault } from "../BaseVault.sol";
import { ContractRegistry } from '../ContractRegistry.sol';

interface IRootChainManager {
    function depositFor(
        address user,
        address rootToken,
        bytes calldata depositData
    ) external;
}

abstract contract L1BalancableVault is BaseVault {
    // L1 block number when L1 last sent liquidity to L2.
    uint256 public lastTransferBlockNum;
    // Amount (in USDC) that L1 last sent to L2 as liquidity.
    uint256 public lastTransferAmount;
    // Last cleared L1 block number when L1 last sent liquidity to L2.
    uint256 public lastClearedTransferBlockNum;
    // Interface for L1 contract registry.
    ContractRegistry public l1ContractRegistry;
    // Amount of debt to L2.
    uint256 public debtToL2;
    // Last cleared L2 block number when L2 last sent liquidity to L1.
    uint256 public lastClearedL2TransferBlockNum;

    constructor(address _l1ContractRegistryAddress) {
        l1ContractRegistry = ContractRegistry(_l1ContractRegistryAddress);
    }

    // This is currently set by defender bot when it observes that some fund has been cleared in L2 staging contract.
    function setlastClearedTransferBlockNum(uint256 _lastClearedTransferBlockNum) external {
        require(msg.sender == l1ContractRegistry.getAddress("Defender"), "L1BalancableVault[setlastClearedTransferBlockNum]: Only defender should be able to set last cleared Transfer block number.");
        lastClearedTransferBlockNum = _lastClearedTransferBlockNum;
    }

    function stagingClearFundCallback(uint256 lastL2TransferBlockNum) external {
        require(msg.sender == l1ContractRegistry.getAddress("L1Staging"), "L1BalancableVault[stagingClearFundCallback]: Only L1 staging should be able call clear fund callback.");
        require(lastL2TransferBlockNum != lastClearedL2TransferBlockNum, "This transfer has already been cleared.");
        lastClearedL2TransferBlockNum = lastL2TransferBlockNum;
    }

    // Called by L1 Fx Tunnel when it recives a message from L2 Fx Tunnel with amount of Debt.
    function addDebtToL2(uint256 amount) external {
        require(msg.sender == l1ContractRegistry.getAddress("L1FxTunnel"), "L1Vault[transferFundsToL2]: Debt can only be updated by L1 Fx Tunnel.");
        debtToL2 = amount;
    }

    function l2Rebalance() external {
        require(msg.sender == l1ContractRegistry.getAddress("Defender"), "L1BalancableVault[setlastClearedTransferBlockNum]: Only defender should be able to set last cleared Transfer block number.");
        _liquidate(debtToL2);
        _transferFundsToL2(debtToL2);
    }

    // Internal function to transfer a certain amount from L1 to L2.
    function _transferFundsToL2(uint256 amount) internal {
        require(lastClearedTransferBlockNum == lastTransferBlockNum, "L2BalancableVault[transferFundsToL2]: Last transfer hasn't been cleared yet.");
        address uscdAddress = l1ContractRegistry.getAddress("L1USDC");
        IERC20(uscdAddress).approve(l1ContractRegistry.getAddress("L2ERC20Predicate"), amount);
        IRootChainManager(l1ContractRegistry.getAddress("L1ChainManager"))
            .depositFor(
                l1ContractRegistry.getAddress("L2Staging"), 
                l1ContractRegistry.getAddress("L1USDC"), 
                abi.encodePacked(amount));
        lastTransferBlockNum = block.number;
        lastTransferAmount = debtToL2;
        debtToL2 = 0;
    }
}