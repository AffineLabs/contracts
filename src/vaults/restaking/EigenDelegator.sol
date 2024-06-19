// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";

import {
    WithdrawalInfo,
    QueuedWithdrawalParams,
    ApproverSignatureAndExpiryParams,
    IDelegationManager,
    IStrategyManager,
    IStrategy
} from "src/interfaces/eigenlayer/eigen.sol";

/**
 * @title AffineDelegator
 * @dev Delegator contract for stETH on Eigenlayer
 */
contract EigenDelegator is Initializable, AffineDelegator, AffineGovernable {
    using SafeTransferLib for ERC20;

    /// @notice StrategyManager for Eigenlayer
    IStrategyManager public constant STRATEGY_MANAGER = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    /// @notice DelegationManager for Eigenlayer
    IDelegationManager public constant DELEGATION_MANAGER =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    /// @notice stETH strategy on Eigenlayer
    IStrategy public constant STAKED_ETH_STRATEGY = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);

    // withdrawals record
    mapping(bytes32 => uint256) public withdrawals;

    /**
     * @dev Initialize the contract
     * @param _vault Vault address
     * @param _operator Operator address
     */
    function initialize(address _vault, address _operator) external initializer {
        vault = _vault;
        asset = ERC20(UltraLRT(vault).asset());
        governance = UltraLRT(vault).governance();
        currentOperator = _operator; // P2P operator
        stETH = IStEth(address(asset));
        stETH.approve(address(STRATEGY_MANAGER), type(uint256).max);
    }

    address public currentOperator;
    // UltraLRT public vault;
    IStEth public stETH;
    uint256 public queuedShares;

    /**
     * @notice Modifier to allow function calls only from the vault or harvester
     * @param amount Amount to delegate
     * @dev Delegate & restake stETH to operator on Eigenlayer
     */
    function _delegate(uint256 amount) internal override {
        // deposit into strategy
        STRATEGY_MANAGER.depositIntoStrategy(address(STAKED_ETH_STRATEGY), address(asset), amount);

        // delegate to operator if not already
        if (DELEGATION_MANAGER.delegatedTo(address(this)) != currentOperator) {
            _delegateToOperator();
        }
    }

    /**
     * @notice Request withdrawal from eigenlayer
     * @param assets Amount to withdraw
     */
    function _requestWithdrawal(uint256 assets) internal override {
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);

        uint256[] memory shares = new uint256[](1);
        shares[0] = Math.min(STAKED_ETH_STRATEGY.underlyingToShares(assets), STAKED_ETH_STRATEGY.shares(address(this)));

        // in any case if converted shares is zero will revert the ops.
        if (shares[0] > 0) {
            queuedShares += shares[0];
            address[] memory strategies = new address[](1);
            strategies[0] = address(STAKED_ETH_STRATEGY);
            params[0] = QueuedWithdrawalParams(strategies, shares, address(this));

            bytes32[] memory withdrawalRoots = DELEGATION_MANAGER.queueWithdrawals(params);
            withdrawals[withdrawalRoots[0]] = shares[0];
        }
    }

    /**
     * @notice Complete withdrawal request
     * @param withdrawalInfo Withdrawal info
     */
    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external {
        require(withdrawalInfo.length == 1, "ED: Invalid info length");

        bytes32 root = DELEGATION_MANAGER.calculateWithdrawalRoot(withdrawalInfo[0]);

        require(DELEGATION_MANAGER.pendingWithdrawals(root), "ED: Invalid withdrawal root");
        require(withdrawals[root] > 0, "ED: Withdrawal not recorded");

        address[][] memory stEthAddresses = new address[][](1);
        address[] memory subAddresses = new address[](1);
        subAddresses[0] = address(stETH);
        stEthAddresses[0] = subAddresses;

        uint256[] memory timeIndex = new uint256[](1);
        timeIndex[0] = 0;

        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = true;
        DELEGATION_MANAGER.completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, timeIndex, receiveAsTokens);

        queuedShares -= withdrawalInfo[0].shares[0];
    }

    /**
     * @notice Record withdrawal request from External requests
     * @param withdrawal Withdrawal info
     */
    function recordWithdrawalsRequest(WithdrawalInfo calldata withdrawal) external onlyHarvester {
        require(
            withdrawal.staker == address(this) && withdrawal.delegatedTo == currentOperator,
            "ED: Invalid staker or operator"
        );

        bytes32 root = DELEGATION_MANAGER.calculateWithdrawalRoot(withdrawal);

        require(DELEGATION_MANAGER.pendingWithdrawals(root), "ED: Invalid withdrawal root");

        require(withdrawals[root] == 0, "ED: Withdrawal already recorded");

        if (withdrawals[root] == 0) {
            withdrawals[root] = withdrawal.shares[0];
            queuedShares += withdrawal.shares[0];
        }
    }

    /**
     * @dev Withdraw stETH from delegator to vault
     */
    function withdraw() external override onlyVault {
        stETH.transferShares(address(vault), stETH.sharesOf(address(this)));
    }

    /**
     * @notice Get withdrawable assets
     * @return withdrawable assets
     */
    function withdrawableAssets() public view override returns (uint256) {
        return STAKED_ETH_STRATEGY.userUnderlyingView(address(this));
    }

    /**
     * @notice Get queued assets
     * @return queued assets
     */
    function queuedAssets() public view override returns (uint256) {
        return STAKED_ETH_STRATEGY.sharesToUnderlyingView(queuedShares) + stETH.balanceOf(address(this));
    }

    /**
     * @dev Delegate to operator
     */
    function _delegateToOperator() internal {
        // delegate to operator
        ApproverSignatureAndExpiryParams memory params = ApproverSignatureAndExpiryParams("", 0);
        DELEGATION_MANAGER.delegateTo(
            currentOperator, params, 0x0000000000000000000000000000000000000000000000000000000000000000
        );
    }
}
