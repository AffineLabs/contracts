// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OmniUltraLRT} from "src/vaults/restaking/omni-lrt/OmniUltraLRT.sol";
import {IPriceFeed} from "src/vaults/restaking/price-feed/IPriceFeed.sol";

contract TmpPriceFeed is IPriceFeed {
    function getPrice() external view returns (uint256, uint256) {
        (1e18, block.timestamp);
    }
}

contract OmniUltraLRTTest is TestPlus {
    using Strings for uint256;

    OmniUltraLRT public vault;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    function setUp() public {
        // choose latest fork
        vm.createSelectFork("ethereum");

        // deploy vault
        vault = OmniUltraLRT(_setupVault());
    }

    function _addWBTC() internal {
        // add WBTC

        vault.addAsset(wbtc, address(0), address(0), address(0));
    }

    function _setupVault() internal returns (address) {
        OmniUltraLRT vaultImpl = new OmniUltraLRT();

        // deploy proxy
        bytes memory initData = abi.encodeCall(
            OmniUltraLRT.initialize,
            ("OmniUltraLRT", "OULRT", wbtc, address(this), address(this), address(this), 0, 0, 0)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImpl), initData);

        return address(proxy);
    }

    function test() public {
        assertTrue(true); // test
    }
}
