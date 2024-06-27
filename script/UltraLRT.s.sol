// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* solhint-disable reason-string, no-console, no-unused-vars */

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
import {UltraLRTRouter} from "src/vaults/restaking/UltraLRTRouter.sol";

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

    function runHoleSkyUltraLRTRouter() public {
        address deployer = _start();

        address hStEth = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
        address hWStEth = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
        address wEth = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;

        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        UltraLRTRouter impl = new UltraLRTRouter();

        bytes memory initData = abi.encodeCall(UltraLRTRouter.initialize, (deployer, wEth, hStEth, hWStEth, permit2));

        console2.logBytes(initData);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        UltraLRTRouter router = UltraLRTRouter(payable(address(proxy)));
        console2.log("router Add %s", address(router));
    }

    /////////////////////////////////////////////////////////////////
    ///                          Mainnet                          ///
    ///                        EigenLayer                         ///
    /////////////////////////////////////////////////////////////////

    function runMainnetEigenBeacon() public {
        address deployer = _start();
        address governance = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;

        // delegator implementation
        EigenDelegator delegatorImpl = new EigenDelegator();
        // beacon
        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);

        console2.log("Main-net eigen delegator beacon Add %s", address(beacon));
    }

    function runMainnetEigenVault() public {
        address deployer = _start();
        // eth time lock contract
        address governance = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;
        // staked eth token
        address stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // mainnet staked eth

        address beacon = 0x4EF63302E9156cFE545dac761AB8D84B786A985F; // mainnet delegator beacon

        UltraLRT vaultImpl = new UltraLRT();

        bytes memory initData = abi.encodeCall(
            UltraLRT.initialize, (governance, stEth, address(beacon), "Liquid ReStaked stEth", "ultraETH")
        );

        console2.logBytes(initData);

        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImpl), initData);
        UltraLRT vault = UltraLRT(address(proxy));

        console2.log("vault Add %s", address(vault));
    }

    function runMainnetEigenDelegatorFactory() public {
        _start();
        UltraLRT vault = UltraLRT(0x5cfD50De188a36d2089927c5a14E143DC65Af780);

        // delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));
        // vault.setDelegatorFactory(address(dFactory)); // need to set this by governance

        console2.log("Factory add %s", address(dFactory));
    }

    function runMainnetEigenEscrow() public {
        _start();
        UltraLRT vault = UltraLRT(0x5cfD50De188a36d2089927c5a14E143DC65Af780);

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        // vault.setWithdrawalEscrow(escrow); // need to set this by governance

        console2.log("escrow address %s", address(escrow));
    }

    /////////////////////////////////////////////////////////////////
    ///                          Mainnet                          ///
    ///                       SymbioticLayer                      ///
    /////////////////////////////////////////////////////////////////

    function runMainnetSymBeacon() public {
        address deployer = _start();
        address governance = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;

        // delegator implementation
        SymbioticDelegator delegatorImpl = new SymbioticDelegator();
        // beacon
        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);

        console2.log("Main-net Symbiotic delegator beacon Add %s", address(beacon));
    }

    function runMainnetSymbioticVault() public {
        address deployer = _start();
        // eth time lock contract
        address governance = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;
        // staked eth token
        address wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

        address beacon = 0x0162B837686DA0c75D323f2071da670b232cBfcc; // mainnet beacon

        UltraLRT vaultImpl = new UltraLRT();

        bytes memory initData = abi.encodeCall(
            UltraLRT.initialize, (governance, wstEth, address(beacon), "Liquid ReStaked wstEth", "ultraETHs")
        );

        console2.logBytes(initData);

        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImpl), initData);
        UltraLRT vault = UltraLRT(address(proxy));

        console2.log("vault Add %s", address(vault));
    }

    function runMainnetSymbioticDelegatorFactory() public {
        _start();
        UltraLRT vault = UltraLRT(0x33795E56250d50065a20E923707fD7396cd938C9); // mainnet vault

        // delegator factory
        SymDelegatorFactory dFactory = new SymDelegatorFactory(address(vault));
        // vault.setDelegatorFactory(address(dFactory)); // need to set this by governance

        console2.log("Factory add %s", address(dFactory));
    }

    function runMainnetSymbioticEscrow() public {
        _start();
        UltraLRT vault = UltraLRT(0x33795E56250d50065a20E923707fD7396cd938C9); // mainnet vault

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        // vault.setWithdrawalEscrow(escrow); // need to set this by governance

        console2.log("escrow address %s", address(escrow));
    }

    //////////////////////////////////////////////////////////
    ///                     Mainnet                        ///
    ///                   UltraLRTRouter                   ///
    //////////////////////////////////////////////////////////

    function runMainetUltraLRTRouter() public {
        address deployer = _start();

        address governance = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;
        address StEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address WStEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        UltraLRTRouter impl = new UltraLRTRouter();

        bytes memory initData = abi.encodeCall(UltraLRTRouter.initialize, (governance, wEth, StEth, WStEth, permit2));

        console2.logBytes(initData);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        UltraLRTRouter router = UltraLRTRouter(payable(address(proxy)));
        console2.log("router Add %s", address(router));
    }
}
