// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {TwoAssetBasket} from "src/vaults/TwoAssetBasket.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC4626Router} from "./ERC4626Router.sol";

contract Router is ERC4626Router {
    constructor(string memory name, address forwarder) ERC4626Router(name) {
        _setTrustedForwarder(forwarder);
    }

    function versionRecipient() external view virtual override returns (string memory) {
        return "1";
    }
}
