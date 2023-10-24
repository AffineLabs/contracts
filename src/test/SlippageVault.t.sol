// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Vault, ERC721} from "src/vaults/Vault.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {SlippageVault} from "src/vaults/SlippageVault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {TestStrategy} from "./mocks/TestStrategy.sol";
import {VaultErrors} from "src/libs/VaultErrors.sol";

import {CommonVaultTest} from "./CommonVault.t.sol";

import "forge-std/console2.sol";

contract SlippageVaultTest is CommonVaultTest {
    function setUp() public virtual override {
        asset = new MockERC20("Mock", "MT", 6);

        SlippageVault sVault = new SlippageVault();
        sVault.initialize(governance, address(asset), "USD Earn", "usdEarn");

        vault = VaultV2(address(sVault));
    }
}
