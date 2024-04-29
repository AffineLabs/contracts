// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// interface Delegator {
// 	address currentOperator;
// 	// address newOperator; 
// 	function delegateToCurrentOperator();
// 	function withdrawFromDelegator();
// 	function redelegate(newOperator);
// 	function requestWithdrawal();
// 	function completeWithdrawalRequest();
// }
interface IDelegationManager {
    function delegateTo(address, bytes calldata, uint256, bytes32) external;
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
    address strategy;
    uint256 shares;
    address recipient;
}

interface IStrategyManager {
    function depositIntoStrategy(address, address, uint256) external;
    function queueWithdrawals(QueuedWithdrawalParams[] calldata) external;
    function completeQueuedWithdrawals(WithdrawalInfo[] calldata, address[] calldata, uint256, bool) external;
}


// upgrading contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

contract AffineDelegator is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, AffineGovernable {
    using SafeTransferLib for ERC20;

    function initialize(address _governance, address _weth, address _operator) external initializer {
        governance = _governance;
        WETH = IWETH(_weth);

        __AccessControl_init();
        __Pausable_init();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GUARDIAN_ROLE, governance);
        _grantRole(HARVESTER_ROLE, governance);
        _setRoleAdmin(APPROVED_TOKEN, bytes32(abi.encodePacked(governance)));
        currentOperator = _operator;
        strategyManager = 0x70f44C13944d49a236E3cD7a94f48f5daB6C619b;
        delegationManager = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
        stEthStrategy = 0x93c4b944D05dfe6df7645A86cd2206016c51564D;

        // pre-approved token

        _grantRole(APPROVED_TOKEN, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84); //stEth
    }

    mapping(address => mapping(address => address)) public strategy;
    IWETH public WETH;

    mapping(address => address) tokenStrategyMapping;
    // Guardian role
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
     // Guardian role
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER");
    // Token approval
    bytes32 public constant APPROVED_TOKEN = keccak256("APPROVED_TOKEN");

    address public currentOperator;
    address public strategyManager;
    address public delegationManager;
    address public stEthStrategy;
    address public harvester;
    address public vault;
    uint256 public queuedWithdrawalAmount;
    uint256 public tvl;
    bool public isDelegated;
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    function delegateToCurrentOperator() external {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "AffineDelegator: Not a guardian");
        // balance of stETH
        uint256 balanceOfStETH = stETH.balanceOf(address(this));
        // approve to strategy manager
        stETH.approve(strategyManager, balanceOfStETH);
        // deposit into strategy
        IStrategyManager(strategyManager).depositIntoStrategy(stEthStrategy, address(stETH), balanceOfStETH);
        tvl += balanceOfStETH;
        if (isDelegated == false) {
            // delegate to operator
            IDelegationManager(delegationManager).delegateTo(currentOperator, "0x", 0, 0x0000000000000000000000000000000000000000000000000000000000000000);
            isDelegated = true;
        }
    }
    
    function setVault(address _vault) external {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "AffineDelegator: Not a guardian");
        vault = _vault;
    }

    function requestWithdrawal(uint256 shares) external {
        require(hasRole(HARVESTER_ROLE, msg.sender), "AffineDelegator: Not a harvester");
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);
        // TODO: need to convert assets to shares
        params[0] = QueuedWithdrawalParams(stEthStrategy, shares, harvester);
        IStrategyManager(strategyManager).queueWithdrawals(params);
        queuedWithdrawalAmount += shares;
    }

    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external {
        require(hasRole(HARVESTER_ROLE, msg.sender), "AffineDelegator: Not a harvestor");
        uint256 balanceOfStETH = stETH.balanceOf(address(this));
        // complete withdrawal request
        address[] memory stEthAddresses = new address[](1);
        stEthAddresses[0] = address(stETH);
        IStrategyManager(strategyManager).completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, 0, true);
        uint256 balanceOfStETHAfter = stETH.balanceOf(address(this));
        uint256 withdrawnTokens = balanceOfStETH - balanceOfStETHAfter;
        stETH.safeTransfer(vault, withdrawnTokens);
        queuedWithdrawalAmount -= withdrawnTokens;
        tvl -= withdrawnTokens;
    }
    // vault
    function delegate(uint256 amount) external {
        require( msg.sender == vault, "AffineDelegator: Not vault");
        // transfer stETH from vault
        stETH.safeTransferFrom(vault, address(this), amount);
        // approve to strategy manager
        stETH.approve(strategyManager, amount);
        // deposit into strategy
        IStrategyManager(strategyManager).depositIntoStrategy(stEthStrategy, address(stETH), amount);
        tvl += amount;
    }

    function vaultInitiateWithdrawal(uint256 shares) external {
        require( msg.sender == vault, "AffineDelegator: Not vault");
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);
        // populate params
        // TODO: need to convert assets to shares
        params[0] = QueuedWithdrawalParams(stEthStrategy, shares, vault);
        IStrategyManager(strategyManager).queueWithdrawals(params);
        queuedWithdrawalAmount += shares;
    }

    function vaultCompleteWithdrawal(WithdrawalInfo[] calldata withdrawalInfo) external {
        require( msg.sender == vault, "AffineDelegator: Not vault");
        // uint256 balanceOfStETH = stETH.balanceOf(address(this));
        // complete withdrawal request
        address[] memory stEthAddresses = new address[](1);
        stEthAddresses[0] = address(stETH);
        IStrategyManager(strategyManager).completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, 0, true);
        // uint256 balanceOfStETHAfter = stETH.balanceOf(address(this));
        // uint256 withdrawnTokens = balanceOfStETH - balanceOfStETHAfter;
        // stETH.safeTransfer(vault, withdrawnTokens);

        // TODO; need to convert shares to assets
        queuedWithdrawalAmount -= withdrawalInfo[0].shares[0];
        tvl -= withdrawalInfo[0].shares[0];
    }

    function checkAssetsAvailibity() external view returns (uint256) {
        return queuedWithdrawalAmount;
    }

    function setHarvester(address _harvester) external {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "AffineDelegator: Not a guardian");
        harvester = _harvester;
        _grantRole(HARVESTER_ROLE, _harvester);
    }


    function setOperator(address _operator) external {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "AffineDelegator: Not a guardian");
        currentOperator = _operator;
    }

    // function delegateToCurrentOperator() external {
    //     require(hasRole(GUARDIAN_ROLE, msg.sender), "AffineDelegator: Not a guardian");
    //     strategy[msg.sender][currentOperator] = currentOperator;
    // }

}