// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// upgrading contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// safeTransfer
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {IWETH} from "src/interfaces/IWETH.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {IWSTETH} from "src/interfaces/lido/IWSTETH.sol";

import {IPermit2} from "src/interfaces/permit2/IPermit2.sol";
import {ISignatureTransfer} from "src/interfaces/permit2/ISignatureTransfer.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

/**
 * @title UltraLRTRouter
 * @dev handle deposits from native, weth, stEth, wStEth to vaults
 */
contract UltraLRTRouter is UUPSUpgradeable, PausableUpgradeable, AffineGovernable {
    using SafeTransferLib for ERC20;

    IWETH public weth;
    IStEth public stEth;
    IWSTETH public wStEth;
    IPermit2 public permit2;

    /**
     * @dev Initialize the contract
     * @param _governance Governance address
     * @param _weth WETH address
     * @param _stEth stETH address
     * @param _wStEth wstETH address
     * @param _permit2 Permit2 address
     */
    function initialize(address _governance, address _weth, address _stEth, address _wStEth, address _permit2)
        external
        initializer
    {
        __Pausable_init();
        governance = _governance;
        weth = IWETH(_weth);
        stEth = IStEth(_stEth);
        wStEth = IWSTETH(_wStEth);
        permit2 = IPermit2(_permit2);
    }

    /**
     * @dev Upgrade the contract
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @notice Pause the contract
    function pause() external onlyGovernance {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyGovernance {
        _unpause();
    }

    /// @notice Fallback function to receive native tokens
    receive() external payable {}

    /**
     * @notice Deposit native tokens to vault
     * @param vault Vault address
     * @param to Receiver address
     */
    function depositNative(address vault, address to) public payable whenNotPaused {
        require(msg.value > 0, "ULRTR: invalid amount");
        _processNativeDeposit(msg.value, vault, to);
    }

    /**
     * @notice Deposit native tokens to vault
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     */
    function _processNativeDeposit(uint256 amount, address vault, address to) internal {
        require(amount > 0, "ULRTR: invalid amount");
        uint256 prevStEthBalance = stEth.balanceOf(address(this));
        stEth.submit{value: amount}(address(0));
        amount = stEth.balanceOf(address(this)) - prevStEthBalance;
        _processDepositFromStEth(amount, vault, to);
    }

    /**
     * @notice Receive asset from user through permit2
     * @param token Token address
     * @param amount Amount to receive
     * @param nonce Nonce
     * @param deadline Deadline of the permit2 approval
     * @param signature Signature of the permit2 approval
     */
    function _receiveAssetFromThroughPermit2(
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) internal {
        permit2.permitTransferFrom(
            // The permit message.
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
                nonce: nonce,
                deadline: deadline
            }),
            // The transfer recipient and amount.
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: amount}),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );
    }

    /**
     * @notice Deposit WETH to vault
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     * @param nonce Nonce
     * @param deadline Deadline of the permit2 approval
     * @param signature Signature of the permit2 approval
     */
    function depositWeth(
        uint256 amount,
        address vault,
        address to,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused {
        _receiveAssetFromThroughPermit2(address(weth), amount, nonce, deadline, signature);
        // weth.transferFrom(msg.sender, address(this), amount);
        weth.withdraw(amount);
        _processNativeDeposit(amount, vault, to);
    }

    /**
     * @notice Deposit stETH to vault
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     * @param nonce Nonce
     * @param deadline Deadline of the permit2 approval
     * @param signature Signature of the permit2 approval
     */
    function depositStEth(
        uint256 amount,
        address vault,
        address to,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused {
        _receiveAssetFromThroughPermit2(address(stEth), amount, nonce, deadline, signature);
        // stEth.transferFrom(msg.sender, address(this), amount);
        _processDepositFromStEth(amount, vault, to);
    }

    /**
     * @notice Deposit wStETH to vault
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     * @param nonce Nonce
     * @param deadline Deadline of the permit2 approval
     * @param signature Signature of the permit2 approval
     */
    function depositWStEth(
        uint256 amount,
        address vault,
        address to,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused {
        _receiveAssetFromThroughPermit2(address(wStEth), amount, nonce, deadline, signature);

        // wStEth.transferFrom(msg.sender, address(this), amount);
        if (UltraLRT(vault).asset() == address(wStEth)) {
            _depositWStEthToVault(amount, vault, to);
        } else if (UltraLRT(vault).asset() == address(stEth)) {
            amount = wStEth.unwrap(amount);
            _depositStEthToVault(amount, vault, to);
        } else {
            revert("Invalid vault");
        }
    }

    /**
     * @notice Process deposit from stEth
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     */
    function _processDepositFromStEth(uint256 amount, address vault, address to) internal {
        if (UltraLRT(vault).asset() == address(stEth)) {
            _depositStEthToVault(amount, vault, to);
        } else if (UltraLRT(vault).asset() == address(wStEth)) {
            ERC20(address(stEth)).safeApprove(address(wStEth), amount);
            amount = wStEth.wrap(amount);
            _depositWStEthToVault(amount, vault, to);
        } else {
            revert("Invalid vault");
        }
    }

    /**
     * @notice Deposit stEth to vault
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     */
    function _depositStEthToVault(uint256 amount, address vault, address to) internal {
        ERC20(address(stEth)).safeApprove(vault, amount);
        UltraLRT(vault).deposit(amount, to);
    }

    /**
     * @notice Deposit wStEth to vault
     * @param amount Amount to deposit
     * @param vault Vault address
     * @param to Receiver address
     */
    function _depositWStEthToVault(uint256 amount, address vault, address to) internal {
        ERC20(address(wStEth)).safeApprove(vault, amount);
        UltraLRT(vault).deposit(amount, to);
    }
}
