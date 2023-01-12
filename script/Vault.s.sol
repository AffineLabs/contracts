// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "../src/both/Vault.sol";

/*  solhint-disable reason-string */

function deployEthVault(address governance, address asset) {
    // Deploy implementation
    Vault impl = new Vault();

    // Initialize proxy with correct data
    bytes memory initData = abi.encodeCall(Vault.initialize, (governance, asset));
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

    // Check that values were set correctly.
    Vault vault = Vault(address(proxy));
    require(vault.governance() == governance);
    require(vault.asset() == asset);
}
