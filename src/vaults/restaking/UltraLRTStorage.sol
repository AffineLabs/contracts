// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

abstract contract UltraLRTStorage {
    struct DelegatorInfo {
        bool isActive;
        uint248 balance;
    }

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");

    bytes32 public constant HARVESTER = keccak256("HARVESTER");

    uint256 public constant MAX_BPS = 10_000;

    uint256 public constant MAX_DELEGATOR = 50;

    // buffer we ignore while resolving shares due to transfer glitch in steth
    uint256 public constant ST_ETH_TRANSFER_BUFFER = 1000;

    // only pausing the deposits in case of limit reached
    uint256 public depositPaused;

    IStEth public constant STETH = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    WithdrawalEscrowV2 public escrow;

    address public beacon;

    address public delegatorFactory;

    uint256 public delegatorAssets;

    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;

    /**
     * @notice A timestamp representing when the most recent harvest occurred.
     * @dev Since the time since the last harvest is used to calculate management fees, this is set
     * to `block.timestamp` (instead of 0) during initialization.
     */
    uint256 public lastHarvest;
    /// @notice The amount of profit *originally* locked after harvesting from a strategy
    uint256 public maxLockedProfit;
    /// @notice Amount of time in seconds that profit takes to fully unlock. See lockedProfit().
    uint256 public constant LOCK_INTERVAL = 24 hours;

    // delegator array
    IDelegator[MAX_DELEGATOR] public delegatorQueue;

    mapping(address => DelegatorInfo) public delegatorMap;

    //active delegator count
    uint256 public delegatorCount;

    // last epoch time
    uint256 public lastEpochTime;

    // max unresolved epochs
    uint256 public maxUnresolvedEpochs;

    modifier whenDepositNotPaused() {
        if (depositPaused != 0) revert ReStakingErrors.DepositPaused();
        _;
    }
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     */
    /// total storage 100
    // 1st slot

    address public migrationVault;
    // have unused 12 bytes in this slot
    // slot 2
    // performance fee charged on profit
    uint256 public performanceFeeBps;
    //  slot 3
    // end epoch interval for withdrawal request
    uint256 public endEpochInterval = LOCK_INTERVAL;
    uint256[97] private __gap;
}
