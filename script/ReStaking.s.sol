// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AffineReStaking} from "src/vaults/restaking/AffineReStaking.sol";

import {Script, console2} from "forge-std/Script.sol";
/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("deployer address %s", deployer);
    }

    function deployReStaking() public {
        _start();

        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address governance = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;

        AffineReStaking impl = new AffineReStaking();

        bytes memory initData = abi.encodeCall(AffineReStaking.initialize, (governance, weth));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        AffineReStaking reStaking = AffineReStaking(address(proxy));
        console2.log("ReStaking Add %s", address(reStaking));

        require(address(reStaking.governance()) == governance, "Invalid gov");
        require(address(reStaking.WETH()) == weth, "invalid weth");
    }
}
