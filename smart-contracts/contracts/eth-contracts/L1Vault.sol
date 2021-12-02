// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseVault } from "../BaseVault.sol";
import { L1BalancableVault } from "./L1BalancableVault.sol";

contract L1Vault is BaseVault, L1BalancableVault {
    // Last cleared L2 block number when L2 last sent liquidity to L1..
    uint256 public lastClearedL2TransferBlockNum;

    constructor(address governance_, address token_, address _l1ContractRegistryAddress) 
    BaseVault(governance_, token_) L1BalancableVault(_l1ContractRegistryAddress) {}

    function clearFund(uint256 lastL2TransferBlockNum, uint256 lastL2TransferAmount) public {
        require(msg.sender == l1ContractRegistry.getAddress("Defender"), "L1Staging[setNewL1TransferDataAndClear]: Only defender should be able to clear fund.");
        require(lastL2TransferBlockNum != lastClearedL2TransferBlockNum, "This transfer has already been cleared.");
        lastClearedL2TransferBlockNum = lastL2TransferBlockNum;
        address uscdAddress = l1ContractRegistry.getAddress("L1USDC");
        IERC20(uscdAddress).transferFrom(l1ContractRegistry.getAddress("Defender"), address(this), lastL2TransferAmount);
    }

    function l2Rebalance() external {
        require(msg.sender == l1ContractRegistry.getAddress("Defender"), "L1BalancableVault[setlastClearedTransferBlockNum]: Only defender should be able to set last cleared Transfer block number.");
        _liquidate(debtToL2);
        _transferFundsToL2(debtToL2);
    }
}
