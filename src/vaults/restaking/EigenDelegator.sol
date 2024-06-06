// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
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
contract EigenDelegator is Initializable, AffineGovernable {
    using SafeTransferLib for ERC20;

    function initialize(address _vault, address _operator) external initializer {
        vault = UltraLRT(_vault);
        governance = vault.governance();
        currentOperator = _operator; // P2P operator
        stETH = IStEth(vault.asset());
        stETH.approve(address(strategyManager), type(uint256).max);
    }

    address public currentOperator;
    IStrategyManager public constant strategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A); // StrategyManager for Eigenlayer
    IDelegationManager public constant delegationManager =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A); // DelegationManager for Eigenlayer
    IStrategy public constant stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D); // stETH strategy on Eigenlayer
    UltraLRT public vault;
    IStEth public stETH;
    uint256 public queuedShares;
    bool public isDelegated;

    modifier onlyVaultOrHarvester() {
        require(
            vault.hasRole(vault.HARVESTER(), msg.sender) || msg.sender == address(vault),
            "AffineDelegator: Not a vault or harvester"
        );
        _;
    }

    /**
     * @dev Delegate & restake stETH to operator on Eigenlayer
     */
    function delegate(uint256 amount) external onlyVaultOrHarvester {
        uint256 balance = stETH.balanceOf(address(this));
        // take stETH from vault
        stETH.transferFrom(address(vault), address(this), amount);
        uint256 transferred = stETH.balanceOf(address(this)) - balance;
        // deposit into strategy
        strategyManager.depositIntoStrategy(address(stEthStrategy), address(stETH), transferred);

        // delegate to operator if not already
        if (!isDelegated) {
            _delegateToOperator();
        }
    }

    /**
     * @dev Request withdrawal from eigenlayer
     */
    function requestWithdrawal(uint256 assets) external onlyVaultOrHarvester {
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);

        uint256[] memory shares = new uint256[](1);
        shares[0] = Math.min(stEthStrategy.underlyingToShares(assets), stEthStrategy.shares(address(this)));

        // in any case if converted shares is zero will revert the ops.
        if (shares[0] > 0) {
            queuedShares += shares[0];
            address[] memory strategies = new address[](1);
            strategies[0] = address(stEthStrategy);
            params[0] = QueuedWithdrawalParams(strategies, shares, address(this));

            delegationManager.queueWithdrawals(params);
        }
    }

    /**
     * @dev Complete withdrawal request from eigenlayer
     */
    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external onlyVaultOrHarvester {
        // complete withdrawal request
        _processWithdrawalRequest(withdrawalInfo, true);
    }

    function completeExternalWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo)
        external
        onlyVaultOrHarvester
    {
        // complete withdrawal request
        _processWithdrawalRequest(withdrawalInfo, false);
    }

    function _processWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo, bool isQueuedShares) internal {
        address[][] memory stEthAddresses = new address[][](1);
        address[] memory subAddresses = new address[](1);
        subAddresses[0] = address(stETH);
        stEthAddresses[0] = subAddresses;

        uint256[] memory timeIndex = new uint256[](1);
        timeIndex[0] = 0;

        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = true;
        delegationManager.completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, timeIndex, receiveAsTokens);

        if (isQueuedShares) {
            queuedShares -= withdrawalInfo[0].shares[0];
        }
    }

    /**
     * @dev Withdraw stETH from delegator to vault
     */
    function withdraw() external onlyVaultOrHarvester {
        stETH.transferShares(address(vault), stETH.sharesOf(address(this)));
    }

    // view functions
    function totalLockedValue() public view returns (uint256) {
        return withdrawableAssets() + queuedAssets();
    }

    function withdrawableAssets() public view returns (uint256) {
        return stEthStrategy.userUnderlyingView(address(this));
    }

    function queuedAssets() public view returns (uint256) {
        return stEthStrategy.sharesToUnderlyingView(queuedShares) + stETH.balanceOf(address(this));
    }

    /**
     * @dev Delegate to operator
     */
    function _delegateToOperator() internal {
        // delegate to operator
        ApproverSignatureAndExpiryParams memory params = ApproverSignatureAndExpiryParams("", 0);
        delegationManager.delegateTo(
            currentOperator, params, 0x0000000000000000000000000000000000000000000000000000000000000000
        );
        isDelegated = true;
    }
}