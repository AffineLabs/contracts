// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* solhint-disable reason-string, no-console */

import {Script, console2} from "forge-std/Script.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {Base} from "./Base.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StrikeEthStrategy} from "src/strategies/StrikeEthStrategy.sol";
import {ICToken} from "src/interfaces/compound/ICToken.sol";

library StrikeFinance {
    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    function _getTestStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }

    function _getEthMainNetUSDCAddr() internal pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _getEthMainNetWEthAddr() internal pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function deployStrikeLevEth(AffineVault vault) internal returns (StrikeEthStrategy strategy) {
        ICToken _aToken = ICToken(0xbEe9Cf658702527b0AcB2719c1FAA29EdC006a92);
        strategy = new StrikeEthStrategy(vault, _aToken, _getStrategists());
    }
}

contract Deploy is Script, Base {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("deployer address %s", deployer);
    }

    function run() external {
        _start();

        AffineVault vault = AffineVault(0xF5c10746B8EE6B69A17f66eCD642d2Fb9df8fcE0);

        require(address(vault.asset()) == StrikeFinance._getEthMainNetWEthAddr(), "Invalid asset");

        StrikeEthStrategy strategy = StrikeFinance.deployStrikeLevEth(vault);

        console2.log("strategy address %s", address(strategy));

        require(address(strategy.asset()) == address(vault.asset()), "Invalid asset");
    }
}
