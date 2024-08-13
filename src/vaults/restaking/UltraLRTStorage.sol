// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

abstract contract UltraLRTStorage {
    // events
    /**
     * @notice An event emitted when the management fee is changed
     * @param oldFee The old management fee
     * @param newFee The new management fee
     */
    event ManagementFeeChanged(uint256 oldFee, uint256 newFee);
    /**
     * @notice An event emitted when the withdrawal fee is changed
     * @param oldFee The old withdrawal fee
     * @param newFee The new withdrawal fee
     */
    event WithdrawalFeeChanged(uint256 oldFee, uint256 newFee);

    /**
     * @notice An event emitted when the performance fee is changed
     * @param oldFee The old performance fee
     * @param newFee The new performance fee
     */
    event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);

    /**
     * @notice An event emitted when the max end epoch interval is changed
     * @param oldInterval The old max end epoch interval
     * @param newInterval The new max end epoch interval
     */
    event MaxEndEpochIntervalChanged(uint256 oldInterval, uint256 newInterval);

    /**
     * @notice An event emitted when the delegator is added
     * @param delegator The delegator address
     * @param operator The operator address
     * @param delegatorCount The total delegator count
     */
    event DelegatorAdded(address delegator, address operator, uint256 delegatorCount);
    /**
     * @notice An event emitted when the delegator is removed
     * @param delegator The delegator address
     * @param delegatorCount The total delegator count
     */
    event DelegatorRemoved(address delegator, uint256 delegatorCount);
    /**
     * @notice An event emitted when the delegator TVL is changed
     * @param delegator The delegator address
     * @param oldBalance The old balance
     * @param newBalance The new balance
     */
    event DelegatorTVLChanged(address delegator, uint256 oldBalance, uint256 newBalance);
    /**
     * @notice An event emitted when the max unresolved epochs is changed
     * @param oldEpochs The old max unresolved epochs
     * @param newEpochs The new max unresolved epochs
     */
    event MaxUnresolvedEpochChanged(uint256 oldEpochs, uint256 newEpochs);
    /**
     * @notice An event emitted when withdrawal is queued
     * @param epoch The epoch number
     * @param receiver The receiver address
     * @param owner The owner address
     * @param shares The shares
     */
    event WithdrawalQueued(uint256 indexed epoch, address receiver, address owner, uint256 shares);
    /**
     * @notice An event emitted when epoch ended
     * @param epoch The epoch number
     * @param shares The shares
     * @param assets The assets
     */
    event EndEpoch(uint256 epoch, uint256 shares, uint256 assets);
    /**
     * @notice An event emitted when the profit is harvested
     * @param profit The profit
     * @param performanceFee Accrued performance fee
     */
    event Harvest(uint256 profit, uint256 performanceFee);

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

    // performance fee charged on profit
    uint256 public performanceFeeBps;
    // accrued performance fee
    // this is the profit that has been harvested but not yet withdrawn
    uint256 public accruedPerformanceFee;

    // max end epoch interval, default 24 hours same as lock interval
    uint256 public maxEndEpochInterval = 24 hours;

    modifier whenDepositNotPaused() {
        if (depositPaused != 0) revert ReStakingErrors.DepositPaused();
        _;
    }
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     */

    uint256[100] private __gap;
}
