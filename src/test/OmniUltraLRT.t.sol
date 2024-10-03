// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OmniUltraLRT} from "src/vaults/restaking/omni-lrt/OmniUltraLRT.sol";
import {IPriceFeed} from "src/vaults/restaking/price-feed/IPriceFeed.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {OmniWithdrawalEscrow} from "src/vaults/restaking/omni-lrt/OmniWithdrawalEscrow.sol";
import {SymDelegatorFactory} from "src/vaults/restaking/SymDelegatorFactory.sol";

contract TmpPriceFeed is IPriceFeed {
    function getPrice() external view returns (uint256, uint256) {
        (1e18, block.timestamp);
    }
}

contract OmniUltraLRTTest is TestPlus {
    using Strings for uint256;

    OmniUltraLRT public vault;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address symbioticWbtcCollateral = 0x971e5b5D4baa5607863f3748FeBf287C7bf82618; // eth symbiotic collateral

    function setUp() public {
        // choose latest fork
        vm.createSelectFork("ethereum");

        // deploy vault
        vault = OmniUltraLRT(_setupVault());

        _addWBTC();
    }

    function _setupWbtcUltraLRT() internal returns (address) {
        UltraLRT wbtcLRT = new UltraLRT();

        SymbioticDelegator delegatorImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), address(this));

        // initialize asset and governanace

        wbtcLRT.initialize(address(this), address(wbtc), address(beacon), "uBTC", "uBTC");

        WithdrawalEscrowV2 _escrow = new WithdrawalEscrowV2(wbtcLRT);

        wbtcLRT.setWithdrawalEscrow(_escrow);

        // set delegator factory
        SymDelegatorFactory dFactory = new SymDelegatorFactory(address(wbtcLRT));

        wbtcLRT.setDelegatorFactory(address(dFactory));

        // set delegator
        wbtcLRT.createDelegator(symbioticWbtcCollateral);

        return address(wbtcLRT);
    }

    function _addWBTC() internal {
        // add WBTC
        // setup omni withdrawal queue
        OmniWithdrawalEscrow escrow = new OmniWithdrawalEscrow(vault, wbtc);
        TmpPriceFeed priceFeed = new TmpPriceFeed();

        address wbtcVault = _setupWbtcUltraLRT();
        vault.addAsset(wbtc, wbtcVault, address(priceFeed), address(escrow));
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
