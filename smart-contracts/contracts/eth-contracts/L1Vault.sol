// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseVault } from "../BaseVault.sol";
import { L1BalancableVault } from "./L1BalancableVault.sol";

contract L1Vault is BaseVault, L1BalancableVault {

    constructor(address governance_, address token_, address _l1ContractRegistryAddress) 
    BaseVault(governance_, token_) L1BalancableVault(_l1ContractRegistryAddress) {}
}
