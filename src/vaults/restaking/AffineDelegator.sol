// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

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

interface IStrategyManager {
    function depositIntoStrategy(address, address, uint256) external;
}

interface IStrategy {
    function underlyingToShares(uint256) external view returns (uint256);
    function sharesToUnderlying(uint256) external view returns (uint256);
    function userUnderlyingView(address) external view returns (uint256);
    function sharesToUnderlyingView(uint256) external view returns (uint256);
}

/**
 * @title AffineDelegator
 * @dev Delegator contract for stETH on Eigenlayer
 */
contract AffineDelegator is Initializable, AffineGovernable {
    using SafeTransferLib for ERC20;

    function initialize(address _vault, address _operator) external initializer {
        vault = UltraLRT(_vault);
        governance = UltraLRT(vault).governance();
        currentOperator = _operator; // P2P operator
        stETH = ERC20(vault.asset());
        stETH.approve(address(strategyManager), type(uint256).max);
    }

    address public currentOperator;
    IStrategyManager public immutable strategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A); // StrategyManager for Eigenlayer
    IDelegationManager public immutable delegationManager =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A); // DelegationManager for Eigenlayer
    IStrategy public immutable stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D); // stETH strategy on Eigenlayer
    UltraLRT public vault;
    ERC20 public stETH;
    uint256 public queuedShares;
    bool public isDelegated;

    modifier onlyHarvester() {
        require(
            vault.hasRole(vault.HARVESTER(), msg.sender) || msg.sender == governance, "AffineDelegator: Not a harvester"
        );
        _;
    }

    modifier onlyVault() {
        require(msg.sender == address(vault), "AffineDelegator: Not vault");
        _;
    }

    /**
     * @dev Delegate & restake stETH to operator on Eigenlayer
     */
    function delegate(uint256 amount) external onlyVault {
        // take stETH from vault
        stETH.safeTransferFrom(address(vault), address(this), amount);

        // deposit into strategy
        strategyManager.depositIntoStrategy(address(stEthStrategy), address(stETH), amount);

        // delegate to operator if not already
        if (!isDelegated) {
            _delegateToOperator();
        }
    }

    /**
     * @dev Request withdrawal from eigenlayer
     */
    function requestWithdrawal(uint256 assets) external onlyVault {
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);

        uint256[] memory shares = new uint256[](1);
        shares[0] = stEthStrategy.underlyingToShares(assets);
        queuedShares += shares[0];

        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);
        params[0] = QueuedWithdrawalParams(strategies, shares, address(this));

        delegationManager.queueWithdrawals(params);
    }

    /**
     * @dev Complete withdrawal request from eigenlayer
     */
    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external onlyHarvester {
        // complete withdrawal request
        address[][] memory stEthAddresses = new address[][](1);
        address[] memory subAddresses = new address[](1);
        subAddresses[0] = address(stETH);
        stEthAddresses[0] = subAddresses;

        uint256[] memory timeIndex = new uint256[](1);
        timeIndex[0] = 0;

        bool[] memory receiveAsTokens = new bool[](1);
        receiveAsTokens[0] = true;
        delegationManager.completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, timeIndex, receiveAsTokens);

        queuedShares -= withdrawalInfo[0].shares[0];
    }

    /**
     * @dev Withdraw stETH from delegator to vault
     */
    function withdraw() external onlyVault {
        stETH.safeTransfer(address(vault), stETH.balanceOf(address(this)));
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
