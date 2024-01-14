// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract Base is Script {
    using stdJson for string;

    struct L1Config {
        address chainManager;
        address erc20Predicate;
        address governance;
        address usdc;
        address weth;
        address wormhole;
    }

    // The chainlink asset / usd (dollars per asset) feeds
    struct Feeds {
        address usdc;
        address wbtc;
        address weth;
    }

    struct L2Config {
        address governance;
        address usdc;
        address wormhole;
        uint256 withdrawFee;
        uint256 managementFee;
        uint256 ewqMinAssets;
        uint256 ewqMinFee;
        address wbtc;
        address weth;
        address wmatic;
        Feeds feeds;
        address aaveRegistry;
    }

    function _getConfigJson(bool mainnet, bool layer1) internal view returns (bytes memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/config.json");
        string memory allJson = vm.readFile(path);
        string memory key = string.concat(".", mainnet ? "mainnet" : "testnet", ".", layer1 ? "l1" : "l2");
        return allJson.parseRaw(key);
    }

    function _getSalt() internal returns (bytes32 salt) {
        string[] memory inputs = new string[](4);
        inputs[0] = "yarn";
        inputs[1] = "--silent";
        inputs[2] = "ts-node";
        inputs[3] = "scripts/utils/get-bytes.ts";
        bytes memory res = vm.ffi(inputs);
        salt = keccak256(res);
    }
}
