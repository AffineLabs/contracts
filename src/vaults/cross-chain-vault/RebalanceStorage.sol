// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {RebalanceModule} from "src/vaults/cross-chain-vault/RebalanceModule.sol";
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

abstract contract RebalanceStorage is AffineGovernable {
    RebalanceModule public rebalanceModule;

    function setRebalanceModule(address _rebalanceModule) external onlyGovernance {
        rebalanceModule = RebalanceModule(_rebalanceModule);
    }
}
