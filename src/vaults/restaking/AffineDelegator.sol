// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IDelegationManager {
    function delegateTo(address, bytes calldata, uint256, bytes32) external;
    function queueWithdrawals(QueuedWithdrawalParams[] calldata) external;
    function completeQueuedWithdrawals(WithdrawalInfo[] calldata, address[] calldata, uint256, bool) external;
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
}

interface IStrategy {
    function underlyingToShares(uint256) external view returns (uint256);
    function sharesToUnderlying(uint256) external view returns (uint256);
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
        stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);

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
    IStrategy public stEthStrategy;
    address public harvester;
    address public vault;
    uint256 public withdrawableAmount;
    uint256 public tvl;
    bool public isDelegated;
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    function delegate() external {
        require(hasRole(HARVESTER_ROLE, msg.sender) || msg.sender == vault, "AffineDelegator: Not a harvester or vault");
        // balance of stETH
        uint256 balanceOfStETH = stETH.balanceOf(address(this));
        // approve to strategy manager
        stETH.approve(strategyManager, balanceOfStETH);
        // deposit into strategy
        IStrategyManager(strategyManager).depositIntoStrategy(address(stEthStrategy), address(stETH), balanceOfStETH);
        tvl += balanceOfStETH;
        if (isDelegated == false) {
            // delegate to operator
            IDelegationManager(delegationManager).delegateTo(currentOperator, "0x", 0, 0x0000000000000000000000000000000000000000000000000000000000000000);
            isDelegated = true;
        }
    }

    function requestWithdrawal(uint256 assets) external {
        require(hasRole(HARVESTER_ROLE, msg.sender), "AffineDelegator: Not a harvester");
        // request withdrawal
        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);
        uint256 shares = stEthStrategy.underlyingToShares(assets);
        params[0] = QueuedWithdrawalParams(address(stEthStrategy), shares, harvester);
        IDelegationManager(delegationManager).queueWithdrawals(params);
    }


    function completeWithdrawalRequest(WithdrawalInfo[] calldata withdrawalInfo) external {
        require(hasRole(HARVESTER_ROLE, msg.sender) || msg.sender == vault, "AffineDelegator: Not a harvestor");
        uint256 balanceOfStETH = stETH.balanceOf(address(this));
        // complete withdrawal request
        address[] memory stEthAddresses = new address[](1);
        stEthAddresses[0] = address(stETH);
        IDelegationManager(delegationManager).completeQueuedWithdrawals(withdrawalInfo, stEthAddresses, 0, true);
        uint256 balanceOfStETHAfter = stETH.balanceOf(address(this));
        uint256 withdrawnTokens = balanceOfStETH - balanceOfStETHAfter;
        withdrawableAmount += withdrawnTokens;
    }

    // vault
    function delegate(uint256 amount) external {
        require( msg.sender == vault, "AffineDelegator: Not vault");
        // transfer stETH from vault
        stETH.safeTransferFrom(vault, address(this), amount);
        // approve to strategy manager
        stETH.approve(strategyManager, amount);
        // deposit into strategy
        IStrategyManager(strategyManager).depositIntoStrategy(address(stEthStrategy), address(stETH), amount);
        tvl += amount;
    }

    function checkAssetsAvailibity() external view returns (uint256) {
        return withdrawableAmount;
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == vault, "AffineDelegator: Not vault");
        require(amount <= withdrawableAmount, "AffineDelegator: Not enough assets");
        stETH.safeTransfer(vault, amount);
        withdrawableAmount -= amount;
        tvl -= amount;
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

    function setVault(address _vault) external {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "AffineDelegator: Not a guardian");
        vault = _vault;
    }

}