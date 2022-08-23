// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { L2Vault } from "../../polygon/L2Vault.sol";
import "../../polygon/TwoAssetBasket.sol";

// Mocks needed to update variables that are in packed slots (forge-std cannot write to packed slots yet)
contract MockL2Vault is L2Vault {
    function setCanTransferToL1(bool _can) external {
        canTransferToL1 = _can;
    }

    function setCanRequestFromL1(bool _can) external {
        canRequestFromL1 = _can;
    }
}
