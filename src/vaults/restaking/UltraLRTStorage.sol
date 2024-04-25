// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";

abstract contract UltraLRTStorage {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");

    bytes32 public constant HARVESTER = keccak256("HARVESTER");

    uint256 public constant MAX_BPS = 10_000;

    uint256 public depositPaused;

    IStEth public constant STETH = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    WithdrawalEscrowV2 public escrow;

    uint256 public delegatorAssets;

    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;

    modifier whenDepositNotPaused() {
        require(depositPaused == 1, "Deposit Paused.");
        _;
    }
}
