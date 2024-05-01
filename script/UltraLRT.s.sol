// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {AffineDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/AffineDelegator.sol";

contract Deploy is Script {
    UltraLRT vault;
    ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;
    IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
    uint256 initAssets;
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        vault = new UltraLRT();

        AffineDelegator delegator = new AffineDelegator();

        vault.initialize(deployer, address(asset), address(delegator), "uLRT", "uLRT");
        vault.createDelegator(operator);

        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);

        vault.setWithdrawalEscrow(escrow);

        console2.log("vault %s", address(vault));
        console2.log("withdrawal escrow %s", address(escrow));
    }
}
