// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Script.sol";

import {Base} from "./Base.sol";
import {Vault} from "../src/both/Vault.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {CurveStrategy} from "../src/ethereum/CurveStrategy.sol";
import {I3CrvMetaPoolZap, ILiquidityGauge, ICurvePool, IMinter} from "../src/interfaces/curve.sol";

/* solhint-disable reason-string */

library EthEntry {
    function deployCurve(BaseVault vault) internal returns (CurveStrategy curve) {
        curve = new CurveStrategy(vault, 
                         ERC20(0x5a6A4D54456819380173272A5E8E9B9904BdF41B),
                         I3CrvMetaPoolZap(0xA79828DF1850E8a3A3064576f380D90aECDD3359), 
                         2,
                         ILiquidityGauge(0xd8b712d29381748dB89c36BCa0138d7c75866ddF)
                         );
        require(address(curve.asset()) == vault.asset());
    }
}

contract Deploy is Script, Base {
    function deployStrategies() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        EthEntry.deployCurve(BaseVault(0x78Bb94Feab383ccEd39766a7d6CF31dED177Ad0c));
    }

    function run() external {
        // Get config info
        bool testnet = vm.envBool("TEST");
        console.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));

        address governance = config.governance;
        address usdc = config.usdc;
        console.log("usdc: %s governance: %s", usdc, governance);

        // Start broadcasting txs
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy implementation
        Vault impl = new Vault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, usdc, "USD Earn Eth", "usdEarnEth"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        Vault vault = Vault(address(proxy));
        require(vault.governance() == governance);
        require(vault.asset() == usdc);
    }
}
