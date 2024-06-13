// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* solhint-disable reason-string, no-console */

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {EigenDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/EigenDelegator.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DelegatorFactory} from "src/vaults/restaking/DelegatorFactory.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {SymDelegatorFactory} from "src/vaults/restaking/SymDelegatorFactory.sol";

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;
        // IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);

        UltraLRT impl = new UltraLRT();
        // delegator implementation
        EigenDelegator delegatorImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), deployer);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (deployer, address(asset), address(beacon), "uLRT", "uLRT"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRT vault = UltraLRT(address(proxy));

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vault.setWithdrawalEscrow(escrow);
        vault.createDelegator(operator);

        console2.log("vault address %s", address(vault));
        console2.log("escrow address %s", address(escrow));
    }

    function _start() internal returns (address) {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        console2.log("deployer gov %s", deployer);
        return deployer;
    }

    function runHoleSky() external {
        address deployer = _start();

        ERC20 asset = ERC20(0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034); // holesky
        // address operator = 0x0a3e3d83C99B27cA7540720b54105C79Cd58dbdD; // holesky
        // IStrategy stEthStrategy = IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3); // holesky

        DelegatorBeacon beacon = DelegatorBeacon(0x75019A4BBCAa8eDA648Af4eeC11290839bC5FcE9);

        UltraLRT impl = UltraLRT(0x7331aD312BAF6CFb127a84DbA077b72295cFEB28);
        // delegator implementation

        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (deployer, address(asset), address(beacon), "ultraETH", "uEth"));
        console2.logBytes(initData);
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRT vault = UltraLRT(address(proxy));

        console2.log("vault address %s", address(vault));
    }

    function runHoleSkyWEscrow() public {
        // add withdrawal escrow
        _start();
        UltraLRT vault = UltraLRT(0x3b07A1A5de80f9b22DE0EC6C44C6E59DDc1C5f41);
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vault.setWithdrawalEscrow(escrow);

        console2.log("escrow address %s", address(escrow));
        // // delegator factory
        // DelegatorFactory dFactory = new DelegatorFactory(address(vault));
        // vault.setDelegatorFactory(address(dFactory));
    }

    function runHoleSkyDFactory() public {
        // add withdrawal escrow
        _start();
        UltraLRT vault = UltraLRT(0x3b07A1A5de80f9b22DE0EC6C44C6E59DDc1C5f41);

        // delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));
        vault.setDelegatorFactory(address(dFactory));

        console2.log("Factory add %s", address(dFactory));
    }

    function runDeposit() public {
        // add withdrawal escrow
        _start();
        UltraLRT vault = UltraLRT(0x3b07A1A5de80f9b22DE0EC6C44C6E59DDc1C5f41);
        ERC20 asset = ERC20(0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034);

        uint256 assets = asset.balanceOf(address(vault));
        // delegator factory
        // asset.approve(address(vault), assets);
        console2.log("assets %s", assets);
        vault.delegateToDelegator(address(vault.delegatorQueue(0)), asset.balanceOf(address(vault)));
    }

    function runSymHoleSky() public {
        address deployer = _start();

        ERC20 asset = ERC20(0x8d09a4502Cc8Cf1547aD300E066060D043f6982D); //wstEth

        // delegator impl
        SymbioticDelegator delImpl = new SymbioticDelegator();

        // del beacon
        DelegatorBeacon beacon = new DelegatorBeacon(address(delImpl), deployer);

        UltraLRT impl = new UltraLRT();

        // initialization data
        bytes memory initData = abi.encodeCall(
            UltraLRT.initialize, (deployer, address(asset), address(beacon), "Symbiotic Ultra LRT", "SYM-uLRT")
        );
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRT vault = UltraLRT(address(proxy));

        console2.log("Beacon %s", address(beacon));
        console2.log("Vault %s", address(vault));
    }

    function runHoleSkyWEscrowSymbiotic() public {
        // add withdrawal escrow
        _start();
        UltraLRT vault = UltraLRT(0x9666aB93452dC300C6b7412936D114bF1F737B1B); // holesky vault for sym
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vault.setWithdrawalEscrow(escrow);

        console2.log("escrow address %s", address(escrow));
    }

    function runHoleSkyDFactorySymbiotic() public {
        // add withdrawal escrow
        _start();
        UltraLRT vault = UltraLRT(0x9666aB93452dC300C6b7412936D114bF1F737B1B); // holesky vault for sym

        // delegator factory
        SymDelegatorFactory dFactory = new SymDelegatorFactory(address(vault));
        vault.setDelegatorFactory(address(dFactory));

        console2.log("Factory add %s", address(dFactory));
    }
}
