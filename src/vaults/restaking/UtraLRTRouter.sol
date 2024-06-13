// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// upgrading contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {IWETH} from "src/interfaces/IWETH.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {IWSTETH} from "src/interfaces/lido/IWSTETH.sol";

// import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";

contract UltraLRTRouter is UUPSUpgradeable, PausableUpgradeable, AffineGovernable {
    IWETH public weth;
    IStEth public stEth;
    IWSTETH public wStEth;

    function initialize(address _governance, address _weth, address _stEth, address _wStEth) external initializer {
        governance = _governance;
        weth = IWETH(_weth);
        stEth = IStEth(_stEth);
        wStEth = IWSTETH(_wStEth);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    receive() external payable {}

    function depositNative(uint256 amount, address vault, address to) public payable {
        require(msg.value != amount || amount > 0, "ULRTR: invalid amount");
        // convert to steth
        amount = stEth.submit{value: amount}(address(0));
        _processDepositFromStEth(amount, vault, to);
    }

    function depositWeth(uint256 amount, address vault, address to) external {
        //TODO receive from permit2
        //transfer
        weth.transferFrom(msg.sender, address(this), amount);
        weth.withdraw(amount);
        depositNative(amount, vault, to);
    }

    function depositStEth(uint256 amount, address vault, address to) external {
        //TODO receive from permit2
        //transfer

        stEth.transferFrom(msg.sender, address(this), amount);
        _processDepositFromStEth(amount, vault, to);
    }

    function depositWStEth(uint256 amount, address vault, address to) external {
        wStEth.transferFrom(msg.sender, address(this), amount);
        if (UltraLRT(vault).asset() == address(wStEth)) {
            _depositWStEthToVault(amount, vault, to);
        } else if (UltraLRT(vault).asset() == address(stEth)) {
            amount = wStEth.unwrap(amount);
            _depositWStEthToVault(amount, vault, to);
        } else {
            revert("Invalid vault");
        }
    }

    function _processDepositFromStEth(uint256 amount, address vault, address to) internal {
        if (UltraLRT(vault).asset() == address(stEth)) {
            _depositStEthToVault(amount, vault, to);
        } else if (UltraLRT(vault).asset() == address(wStEth)) {
            stEth.approve(address(wStEth), amount);
            amount = wStEth.wrap(amount);
            _depositStEthToVault(amount, vault, to);
        } else {
            revert("Invalid vault");
        }
    }

    function _depositStEthToVault(uint256 amount, address vault, address to) internal {
        stEth.approve(vault, amount);
        UltraLRT(vault).deposit(amount, to);
    }

    function _depositWStEthToVault(uint256 amount, address vault, address to) internal {
        wStEth.approve(vault, amount);
        UltraLRT(vault).deposit(amount, to);
    }
}
