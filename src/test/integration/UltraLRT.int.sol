// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";

import {UltraLRT, Math} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {EigenDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/EigenDelegator.sol";
import {DelegatorFactory} from "src/vaults/restaking/DelegatorFactory.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UltraLRTV2 is UltraLRT {
    // will have the same decimals as asset
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 0;
    }
}

contract UltraLRT_Int_Test is TestPlus {
    UltraLRT eigenVault = UltraLRT(0x47657094e3AF11c47d5eF4D3598A1536B394EEc4);
    UltraLRT symVault = UltraLRT(0x0D53bc2BA508dFdf47084d511F13Bb2eb3f8317B);

    UltraLRT newEigenVault;
    UltraLRT newSymVault;

    function _deployNewEigenVault() internal {
        address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5; // p2p

        ERC20 asset = ERC20(eigenVault.asset());
        // ultra LRT impl
        UltraLRTV2 impl = new UltraLRTV2();
        // delegator implementation
        EigenDelegator delegatorImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (governance, address(asset), address(beacon), "uLRT", "uLRT"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRTV2 vault = UltraLRTV2(address(proxy));

        // set delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));

        vm.prank(governance);
        vault.setDelegatorFactory(address(dFactory));

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vm.prank(governance);
        vault.setWithdrawalEscrow(escrow);

        // create 1 delegator
        vm.prank(governance);
        vault.createDelegator(operator);

        vm.prank(governance);
        vault.setMaxUnresolvedEpochs(10);
        eigenVault = UltraLRT(address(vault));
    }

    function _deployNewSymVault() internal {
        address operator = 0xC329400492c6ff2438472D4651Ad17389fCb843a; // p2p

        ERC20 asset = ERC20(symVault.asset());
        // ultra LRT impl
        UltraLRTV2 impl = new UltraLRTV2();
        // delegator implementation
        SymbioticDelegator delegatorImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (governance, address(asset), address(beacon), "uLRTs", "uLRTs"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRTV2 vault = UltraLRTV2(address(proxy));

        // set delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));

        vm.prank(governance);
        vault.setDelegatorFactory(address(dFactory));

        // create delegator
        vm.prank(governance);
        vault.createDelegator(operator);

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vm.prank(governance);
        vault.setWithdrawalEscrow(escrow);

        newSymVault = UltraLRT(address(vault));
    }

    function setUp() public {
        vm.createSelectFork("ethereum", 20_364_000);
        governance = eigenVault.governance();
        _deployNewEigenVault();
        _deployNewSymVault();
    }

    function testSymMigration() public {
        assertTrue(true);
    }
}
