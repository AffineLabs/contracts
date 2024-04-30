// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IDelegationManager {
    function delegateTo(address, ApproverSignatureAndExpiryParams calldata, bytes32) external;
    function queueWithdrawals(QueuedWithdrawalParams[] calldata) external;
    function completeQueuedWithdrawals(WithdrawalInfo[] calldata, address[][] calldata, uint256[] calldata, bool[] calldata) external;
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
}

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

contract AffineDelegator is AffineGovernable {
    using SafeTransferLib for ERC20;

    constructor(address _governance, address _vault, address _operator) {
        governance = _governance;
        // All roles use the default admin role
        // Governance has the admin role and all roles
        currentOperator = _operator; // P2P
        strategyManager = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;
        delegationManager = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        vault = _vault;
        stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        stETH.approve(strategyManager, type(uint256).max);
    }

    mapping(address => mapping(address => address)) public strategy;

    mapping(address => address) tokenStrategyMapping;

    address public currentOperator;
    address public strategyManager;
    address public delegationManager;
    IStrategy public stEthStrategy;
    address public harvester;
    address public vault;
    uint256 public withdrawableAmount;
    uint256 public tvl;
    bool public isDelegated;
    ERC20 public stETH;

    function delegate(uint256 amount) external {
        require(msg.sender == harvester || msg.sender == vault, "AffineDelegator: Not a harvester or vault");
        // take stETH from vault
        stETH.safeTransferFrom(vault, address(this), amount);

        // deposit into strategy
        // IDelegationManager(delegationManager).delegateTo(currentOperator, "", 0, 0x0000000000000000000000000000000000000000000000000000000000000000);
        IStrategyManager(strategyManager).depositIntoStrategy(address(stEthStrategy), address(stETH), amount);
        uint256 shares = stEthStrategy.underlyingToShares(amount);
        tvl += shares;
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
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);
        params[0] = QueuedWithdrawalParams(strategies, shares, address(this));
        IDelegationManager(delegationManager).queueWithdrawals(params);
    }

    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external {
        require(msg.sender == harvester|| msg.sender == vault, "AffineDelegator: Not a harvestor");
        uint256 balanceOfStETH = stETH.balanceOf(address(this));
        // complete withdrawal request
        address[][] memory stEthAddresses = new address[][](1);
        address[] memory x = new address[](1);
        x[0] = address(stETH);
        stEthAddresses[0] = x;

        uint256[] memory timeIndex = new uint256[](1);
        timeIndex[0] = 0;

        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = true;
        IDelegationManager(delegationManager).completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, timeIndex, receiveAsTokens);
        uint256 balanceOfStETHAfter = stETH.balanceOf(address(this));
        uint256 withdrawnTokens = balanceOfStETHAfter - balanceOfStETH;
        withdrawableAmount += withdrawnTokens;
    }


    function withdraw() external {
        require(msg.sender == vault, "AffineDelegator: Not vault");
        stETH.safeTransfer(vault, withdrawableAmount);
        uint256 shares = stEthStrategy.underlyingToShares(withdrawableAmount);
        tvl -= shares;
        withdrawableAmount = 0;
    }

    function setHarvester(address _harvester) external onlyGovernance {
        harvester = _harvester;
    }

    function setVault(address _vault) external onlyGovernance {
        vault = _vault;
    }

    function totalLockedValue() external view returns (uint256) {
        return tvl;
    }

    function _delegateToOperator() internal {
        // delegate to operator
        ApproverSignatureAndExpiryParams memory params = ApproverSignatureAndExpiryParams("", 0);
        IDelegationManager(delegationManager).delegateTo(
            currentOperator, 
            params,
            0x0000000000000000000000000000000000000000000000000000000000000000
        );
        isDelegated = true;
    }

}