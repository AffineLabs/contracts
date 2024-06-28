// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DefaultCollateral is ERC20Upgradeable {
    using SafeERC20 for IERC20;

    uint8 private DECIMALS;
    /**
     * @dev ICollateral
     */
    address public asset;

    /**
     * @dev ICollateral
     */
    uint256 public totalRepaidDebt;

    /**
     * @dev ICollateral
     */
    mapping(address => uint256) public issuerRepaidDebt;

    /**
     * @dev ICollateral
     */
    mapping(address => uint256) public recipientRepaidDebt;

    /**
     * @dev ICollateral
     */
    mapping(address => mapping(address => uint256)) public repaidDebt;

    /**
     * @dev ICollateral
     */
    uint256 public totalDebt;

    /**
     * @dev ICollateral
     */
    mapping(address => uint256) public issuerDebt;

    /**
     * @dev ICollateral
     */
    mapping(address => uint256) public recipientDebt;

    /**
     * @dev ICollateral
     */
    mapping(address => mapping(address => uint256)) public debt;

    /**
     * @dev IDefaultCollateral
     */
    uint256 public limit;

    /**
     * @dev IDefaultCollateral
     */
    address public limitIncreaser;

    modifier onlyLimitIncreaser() {
        if (msg.sender != limitIncreaser) {
            revert("");
        }
        _;
    }

    function initialize(address asset_, uint256 initialLimit, address limitIncreaser_) external initializer {
        __ERC20_init(
            string.concat("DefaultCollateral_", IERC20Metadata(asset_).name()),
            string.concat("DC_", IERC20Metadata(asset_).symbol())
        );

        asset = asset_;

        limit = initialLimit;
        limitIncreaser = limitIncreaser_;

        DECIMALS = IERC20Metadata(asset).decimals();
    }

    /**
     * @dev ERC20Upgradeable
     */
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @dev IDefaultCollateral
     */
    function deposit(address recipient, uint256 amount) public returns (uint256) {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        amount = IERC20(asset).balanceOf(address(this)) - balanceBefore;

        if (amount == 0) {
            revert("");
        }

        if (totalSupply() + amount > limit) {
            revert("");
        }

        _mint(recipient, amount);

        //emit Deposit(msg.sender, recipient, amount);

        return amount;
    }

    /**
     * @dev IDefaultCollateral
     */
    function withdraw(address recipient, uint256 amount) external {
        if (amount == 0) {
            revert("");
        }

        _burn(msg.sender, amount);

        IERC20(asset).safeTransfer(recipient, amount);

        //emit Withdraw(msg.sender, recipient, amount);
    }

    /**
     * @dev ICollateral
     */
    function issueDebt(address recipient, uint256 amount) external {
        if (amount == 0) {
            revert("");
        }

        _burn(msg.sender, amount);

        //emit IssueDebt(msg.sender, recipient, amount);

        totalRepaidDebt += amount;
        issuerRepaidDebt[msg.sender] += amount;
        recipientRepaidDebt[recipient] += amount;
        repaidDebt[msg.sender][recipient] += amount;

        IERC20(asset).safeTransfer(recipient, amount);

        //emit RepayDebt(msg.sender, recipient, amount);
    }

    /**
     * @dev IDefaultCollateral
     */
    function increaseLimit(uint256 amount) external onlyLimitIncreaser {
        limit += amount;

        //emit IncreaseLimit(amount);
    }

    /**
     * @dev IDefaultCollateral
     */
    function setLimitIncreaser(address limitIncreaser_) external onlyLimitIncreaser {
        limitIncreaser = limitIncreaser_;

        //emit SetLimitIncreaser(limitIncreaser_);
    }
}
