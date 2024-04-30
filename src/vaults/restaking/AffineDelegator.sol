// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IDelegationManager {
    function delegateTo(address, ApproverSignatureAndExpiryParams calldata, bytes32) external;
    function queueWithdrawals(QueuedWithdrawalParams[] calldata) external;
    function completeQueuedWithdrawals(
        WithdrawalInfo[] calldata,
        address[][] calldata,
        uint256[] calldata,
        bool[] calldata
    ) external;
}

struct WithdrawalInfo {
    address staker;
    address delegatedTo;
    address withdrawer;
    uint256 nonce;
    uint32 startBlock;
    address[] strategies;
    uint256[] shares;
}

struct QueuedWithdrawalParams {
    address[] strategies;
    uint256[] shares;
    address recipient;
}

struct ApproverSignatureAndExpiryParams {
    bytes signature;
    uint256 expiry;
}

interface IStrategyManager {
    function depositIntoStrategy(address, address, uint256) external;
}

interface IStrategy {
    function underlyingToShares(uint256) external view returns (uint256);
    function sharesToUnderlying(uint256) external view returns (uint256);
    function userUnderlyingView(address) external view returns (uint256);
    function sharesToUnderlyingView(uint256) external view returns (uint256);
}

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

contract AffineDelegator is Initializable, AccessControl, AffineGovernable {
    using SafeTransferLib for ERC20;

    function initialize(address _vault, address _operator) external initializer {
        vault = _vault;
        governance = UltraLRT(vault).governance();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        currentOperator = _operator; // P2P
        strategyManager = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;
        delegationManager = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);

        stETH = ERC20(UltraLRT(vault).asset());

        stETH.approve(strategyManager, type(uint256).max);

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(HARVESTER_ROLE, governance);
    }

    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER");

    mapping(address => mapping(address => address)) public strategy;

    mapping(address => address) tokenStrategyMapping;

    address public currentOperator;
    address public strategyManager;
    address public delegationManager;
    IStrategy public stEthStrategy;
    address public harvester;
    address public vault;
    uint256 public withdrawableAmount;
    uint256 public queuedShares;

    bool public isDelegated;
    ERC20 public stETH;

    // TODO replace require with role check and modifier
    function delegate(uint256 amount) external {
        require(msg.sender == harvester || msg.sender == vault, "AffineDelegator: Not a harvester or vault");
        // take stETH from vault
        stETH.safeTransferFrom(vault, address(this), amount);

        // deposit into strategy
        // IDelegationManager(delegationManager).delegateTo(currentOperator, "", 0, 0x0000000000000000000000000000000000000000000000000000000000000000);
        IStrategyManager(strategyManager).depositIntoStrategy(address(stEthStrategy), address(stETH), amount);

        if (!isDelegated) {
            _delegateToOperator();
        }
    }

    function requestWithdrawal(uint256 assets) external {
        require(msg.sender == harvester || msg.sender == vault, "AffineDelegator: Not a harvester");
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = stEthStrategy.underlyingToShares(assets);
        queuedShares += shares[0];

        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);
        params[0] = QueuedWithdrawalParams(strategies, shares, address(this));
        IDelegationManager(delegationManager).queueWithdrawals(params);
    }

    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external {
        // TODO directly check harvester role from vault.
        require(msg.sender == harvester || msg.sender == vault, "AffineDelegator: Not a harvester");
        // complete withdrawal request
        address[][] memory stEthAddresses = new address[][](1);
        address[] memory x = new address[](1);
        x[0] = address(stETH);
        stEthAddresses[0] = x;

        uint256[] memory timeIndex = new uint256[](1);
        timeIndex[0] = 0;

        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = true;
        IDelegationManager(delegationManager).completeQueuedWithdrawals(
            withdrawalInfo, stEthAddresses, timeIndex, receiveAsTokens
        );

        queuedShares -= withdrawalInfo[0].shares[0];
    }

    function withdraw() external {
        require(msg.sender == vault, "AffineDelegator: Not vault");
        stETH.safeTransfer(vault, stETH.balanceOf(address(this)));
    }

    function setHarvester(address _harvester) external onlyGovernance {
        harvester = _harvester;
    }

    function setVault(address _vault) external onlyGovernance {
        vault = _vault;
    }

    function totalLockedValue() external view returns (uint256) {
        return stEthStrategy.userUnderlyingView(address(this)) + stEthStrategy.sharesToUnderlyingView(queuedShares)
            + stETH.balanceOf(address(this));
    }

    function _delegateToOperator() internal {
        // delegate to operator
        ApproverSignatureAndExpiryParams memory params = ApproverSignatureAndExpiryParams("", 0);
        IDelegationManager(delegationManager).delegateTo(
            currentOperator, params, 0x0000000000000000000000000000000000000000000000000000000000000000
        );
        isDelegated = true;
    }
}
