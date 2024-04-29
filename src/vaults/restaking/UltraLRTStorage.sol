// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";

abstract contract UltraLRTStorage {
    struct DelegatorInfo {
        bool isActive;
        uint248 balance;
    }

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");

    bytes32 public constant HARVESTER = keccak256("HARVESTER");

    uint256 public constant MAX_BPS = 10_000;

    uint256 public constant MAX_DELEGATOR = 100;

    uint256 public depositPaused;

    IStEth public constant STETH = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    WithdrawalEscrowV2 public escrow;

    uint256 public delegatorAssets;

    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;

    // delegator array
    IDelegator[MAX_DELEGATOR] public delegatorQueue;
    mapping(address => DelegatorInfo) public delegatorMap;

    //active delegator count
    uint256 delegatorCount;

    modifier whenDepositNotPaused() {
        require(depositPaused == 1, "Deposit Paused.");
        _;
    }
}
