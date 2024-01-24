// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "./AccessStrategy.sol";
import {EthVaultV2} from "src/vaults/EthVaultV2.sol";

import {L1WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/L2WormholeRouter.sol";
import {L1BaseBridgeEscrow} from "src/vaults/cross-chain-vault/escrow/L1BaseBridgeEscrow.sol";

contract LevEthL1 is AccessStrategy {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;

    L1WormholeRouter public immutable wormholeRouter;
    L1BaseBridgeEscrow public escrow;
    address public l2EscrowAddress;
    


    IWETH public constant WETH = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    constructor(AffineVault _vault, L1WormholeRouter _router, L1BaseBridgeEscrow _escrow, address[] memory strategists) AccessStrategy(_vault, strategists) {
        wormholeRouter  = _router;
        escrow          = _escrow;
        asset.approve(address(_vault), type(uint256).max);
        asset.approve(address(_escrow), type(uint256).max);
    }

    function setL2Escrow(address _l2EscrowAddress) external  onlyRole(STRATEGIST_ROLE) {
        l2EscrowAddress = _l2EscrowAddress;
    }

    /*//////////////////////////////////////////////////////////////
                               INVESTMENT
    //////////////////////////////////////////////////////////////*/

    function _buyVault(uint256 amount) internal {
        require(amount > 0, "Can't buy 0");
        uint256 balance = asset.balanceOf(address(this));
        require(balance >= amount, "Not enough balance");
        vault.deposit(ammount, address(this));
    }
    

    function buyVault(uint256 amount) external  onlyRole(STRATEGIST_ROLE) {
        _buyVault(amount);
    }

    function _sellVault(uint256 amount) internal {
        require(amount > 0, "Can't sell 0");
        vault.Withdraw(ammount, address(this), address(this));
    }

    function sellVault(uint256 amount) external  onlyRole(STRATEGIST_ROLE) {
        _sellVault(amount);
    }

    event TransferToL2(uint256 assetsRequested, uint256 assetsSent);

    function _sendToL2(uint256 amount) internal {
        uint256 contractBalance = asset.balanceOf(address(this));
        require(contractBalance >= amount, "Not enough balance");
        // unwrap WETH
        WETH.withdraw(amount);

        uint256 amountToSend = Math.min(amount, address(this).balance);
        escrow.bridge{value: amountToSend}(
            l2EscrowAddress,
            contractBalance
        );

        L1WormholeRouter(wormholeRouter).reportFundTransfer(amountToSend);
        emit TransferToL2({assetsRequested: amountRequested, assetsSent: amountToSend});
    }

    function sendToL2(uint256 amount) external onlyRole(STRATEGIST_ROLE) {
        _sendToL2(amount);
    }

    /*//////////////////////////////////////////////////////////////
                               DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    function afterReceive() external {
        require(msg.sender == address(escrow), "L1: only escrow");
        uint256 balance = asset.balanceOf(address(this));
        _buyVault(balance);
    }

    function processFundRequest(uint256 amountRequested) external {
        require(msg.sender == address(wormholeRouter), "L1: only router");
        _sellVault(amountRequested);
        uint256 amountToSend = Math.min(asset.balanceOf(address(this)), amountRequested);
        _sendToL2(amountToSend);
    }



    /*//////////////////////////////////////////////////////////////
                             TVL ESTIMATION
    //////////////////////////////////////////////////////////////*/
    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset() + aToken.balanceOf(address(this));
    }
}
