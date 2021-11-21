// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import { BaseVault } from "../BaseVault.sol";

contract L1Vault is BaseVault {
    constructor(address governance_, address token_) BaseVault(governance_, token_) {}
}
