// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {TwoAssetBasket} from "./TwoAssetBasket.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC4626Router} from "../polygon/ERC4626Router.sol";

contract Router is ERC4626Router {
    constructor(string memory name, address forwarder) ERC4626Router(name) {
        _setTrustedForwarder(forwarder);
    }

    function versionRecipient() external view virtual override returns (string memory) {
        return "1";
    }
}
