// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// upgrading contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

contract AffineReStaking is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, AffineGovernable {
    using SafeTransferLib for ERC20;

    function initialize(address _governance, address _weth) external initializer {
        governance = _governance;
        WETH = IWETH(_weth);

        __AccessControl_init();
        __Pausable_init();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GUARDIAN_ROLE, governance);
        _setRoleAdmin(APPROVED_TOKEN, bytes32(abi.encodePacked(governance)));

        // pre-approved token

        _grantRole(APPROVED_TOKEN, 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee); //weEth
        _grantRole(APPROVED_TOKEN, 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7); //rsEth
        _grantRole(APPROVED_TOKEN, 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110); //ezEth
        _grantRole(APPROVED_TOKEN, 0x628eBC64A38269E031AFBDd3C5BA857483B5d048); //lsEth
        _grantRole(APPROVED_TOKEN, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); //wstEth
        _grantRole(APPROVED_TOKEN, 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0); //rswEth
        _grantRole(APPROVED_TOKEN, 0xf951E335afb289353dc249e82926178EaC7DEd78); //swEth
        _grantRole(APPROVED_TOKEN, address(WETH)); // weth
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    // Guardian role
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    // Token approval
    bytes32 public constant APPROVED_TOKEN = keccak256("APPROVED_TOKEN");

    IWETH public WETH;
    // token amount from user
    mapping(address => mapping(address => uint256)) public balance;

    // event id for each event
    uint256 private eventId;

    // paused deposit
    uint256 public depositPaused;

    modifier whenDepositNotPaused() {
        require(depositPaused == 0, "AR: deposit paused");
        _;
    }

    function pauseDeposit() external onlyGovernance {
        depositPaused = 1;
    }

    function resumeDeposit() external onlyGovernance {
        depositPaused = 0;
    }

    // Approve token for deposit
    function approveToken(address _token) external onlyGovernance {
        if (hasRole(APPROVED_TOKEN, _token)) revert ReStakingErrors.AlreadyApprovedToken();
        _grantRole(APPROVED_TOKEN, _token);
    }

    // Revoke token
    function revokeToken(address _token) external onlyGovernance {
        if (!hasRole(APPROVED_TOKEN, _token)) revert ReStakingErrors.NotApprovedToken();
        _revokeRole(APPROVED_TOKEN, _token);
    }

    event Deposit(uint256 indexed eventId, address indexed depositor, address indexed token, uint256 amount);
    // deposit token for

    function depositFor(address _token, address _for, uint256 _amount) external whenNotPaused whenDepositNotPaused {
        if (_amount == 0) revert ReStakingErrors.DepositAmountCannotBeZero();
        if (_for == address(0)) revert ReStakingErrors.CannotDepositForZeroAddress();
        if (!hasRole(APPROVED_TOKEN, _token)) revert ReStakingErrors.TokenNotAllowedForStaking();

        balance[_token][_for] += _amount;

        emit Deposit(++eventId, _for, _token, _amount);

        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function depositETHFor(address _for) external payable whenNotPaused whenDepositNotPaused {
        if (msg.value == 0) revert ReStakingErrors.DepositAmountCannotBeZero();
        if (_for == address(0)) revert ReStakingErrors.CannotDepositForZeroAddress();
        if (!hasRole(APPROVED_TOKEN, address(WETH))) revert ReStakingErrors.TokenNotAllowedForStaking();

        balance[address(WETH)][_for] += msg.value;
        emit Deposit(++eventId, _for, address(WETH), msg.value);

        WETH.deposit{value: msg.value}();
    }

    event Withdraw(uint256 indexed eventId, address indexed withdrawer, address indexed token, uint256 amount);

    function withdraw(address _token, uint256 _amount) external whenNotPaused {
        if (_amount == 0) revert ReStakingErrors.WithdrawAmountCannotBeZero();
        if (balance[_token][msg.sender] < _amount) revert ReStakingErrors.InvalidWithdrawalAmount();

        balance[_token][msg.sender] -= _amount;
        emit Withdraw(++eventId, msg.sender, _token, _amount);

        ERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice Pause the contract
    function pause() external onlyGovernance {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyGovernance {
        _unpause();
    }
}
