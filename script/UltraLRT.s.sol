// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* solhint-disable reason-string, no-console */

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {AffineDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/AffineDelegator.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;
    IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
    uint256 initAssets;

    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        UltraLRT impl = new UltraLRT();
        // delegator implementation
        AffineDelegator delegatorImpl = new AffineDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), deployer);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (deployer, address(asset), address(beacon), "uLRT", "uLRT"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRT vault = UltraLRT(address(proxy));

        initAssets = 10 ** asset.decimals();
        initAssets *= 100;

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vault.setWithdrawalEscrow(escrow);
        vault.createDelegator(operator);

        console2.log("vault address %s", address(vault));
        console2.log("escrow address %s", address(escrow));
    }

    function run2() public {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        UltraLRT vault = UltraLRT(0xeA8AE08513f8230cAA8d031D28cB4Ac8CE720c68);
        asset.approve(address(vault), 10 * 1e18);
        vault.deposit(10 * 1e18, deployer);

        console2.log("dep shares %s", vault.balanceOf(deployer));
        console2.log("dep assets %s", vault.previewRedeem(vault.balanceOf(deployer)));
    }
}
