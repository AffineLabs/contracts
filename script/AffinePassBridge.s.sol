// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AffinePass} from "src/incentives/AffinePass.sol";
import {AffinePassBridge} from "src/incentives/AffinePassBridge.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function _deployProxy(address impl) internal returns (AffinePassBridge bridge) {
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        bridge = AffinePassBridge(payable(address(proxy)));
    }

    function _deployBridge(AffinePass affinePass, address router) internal {
        // Deploy implementation
        AffinePassBridge impl = new AffinePassBridge(affinePass, router);

        // Deploy Proxy
        AffinePassBridge bridge = _deployProxy(address(impl));

        // Do some checks
        require(bridge.paused() == false);
        require(bridge.getRouter() == router);
    }

    function runMumbai() external {
        _start();

        address router = 0x70499c328e1E2a3c41108bd3730F6670a44595D1;
        AffinePass affinePass = AffinePass(0xde673348cC0EE97Ca631278cAAfD82008D153582);

        _deployBridge(affinePass, router);
    }

    function runPolygon() external {
        _start();

        address router = 0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43;
        AffinePass affinePass = AffinePass(0x962E765A68C12e5c890589Ba66bfd848d0Ee52C5);

        _deployBridge(affinePass, router);
    }

    function runSepolia() external {
        _start();

        address router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf;
        AffinePass affinePass = AffinePass(0x8A9DcE4B2d88b55c2E49E29391289bB09fb1d7c2);

        _deployBridge(affinePass, router);
    }

    function runEth() external {
        _start();

        address router = 0xE561d5E02207fb5eB32cca20a699E0d8919a1476;
        AffinePass affinePass = AffinePass(address(0));

        _deployBridge(affinePass, router);
    }
}
