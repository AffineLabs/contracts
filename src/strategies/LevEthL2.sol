// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "./AccessStrategy.sol";

import {L2WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/L2WormholeRouter.sol";
import {L2BaseBridgeEscrow} from "src/vaults/cross-chain-vault/escrow/L2BaseBridgeEscrow.sol";

contract LevEthL2 is AccessStrategy {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;

    L2WormholeRouter public immutable wormholeRouter;
    L2BaseBridgeEscrow public escrow;
    address public l1EscrowAddress;
    bool canRequest = true;
    bool canTransfer = true;
    uint256 requestedAmount = 0;

    IWETH public constant WETH = IWETH(payable(0x4200000000000000000000000000000000000006));

    constructor(AffineVault _vault, L2WormholeRouter _router, L2BaseBridgeEscrow _escrow, address[] memory strategists) AccessStrategy(_vault, strategists){
        wormholeRouter  = _router;
        escrow          = _escrow;
    }

    /*//////////////////////////////////////////////////////////////
                               INVESTMENT
    //////////////////////////////////////////////////////////////*/
    function _afterInvest(uint256 amount) internal override {
        // TODO: Deposit ETH into L1
        if (amount == 0) return;
    }

    function setL1Escrow(address _l1EscrowAddress) external onlyRole(STRATEGIST_ROLE) {
        l1EscrowAddress = _l1EscrowAddress;
    }

    function sendToL1(uint256 amount, int64 _relayerFeePct) external payable onlyRole(STRATEGIST_ROLE) {
        uint256 wethBalance = asset.balanceOf(address(this));

        // Unwrap WETH
        WETH.withdraw(wethBalance);

        uint256 amountToSend = Math.min(amount, address(this).balance);
        escrow.bridge{value: amountToSend}(
            address(l1EscrowAddress),
            amountToSend,
            _relayerFeePct
        );
        canTransfer = false;
    }

    function afterTransfer() external onlyRole(STRATEGIST_ROLE) {
        canTransfer = true;
    }

    /*//////////////////////////////////////////////////////////////
                               DIVESTMENT
    //////////////////////////////////////////////////////////////*/
    function _divest(uint256 assets) internal override returns (uint256) {
        // Withdraw only the needed amounts from the lending pool
        uint256 currAssets = balanceOfAsset();
        uint256 assetsReq = currAssets >= assets ? 0 : assets - currAssets;

        // Don't try to withdraw more
        if (assetsReq != 0) {
            uint256 assetsToWithdraw = Math.min(assetsReq, balanceOfAsset());
            requestedAmount+=assetsToWithdraw;
        }

        uint256 amountToSend = Math.min(assets, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function requestFunds() external onlyRole(STRATEGIST_ROLE) {
        require(canRequest, "Can't request funds yet");
        require(requestedAmount > 0, "No funds requested");
        wormholeRouter.requestFunds(requestedAmount);
        requestedAmount = 0;
        canRequest = false;
    }

    function afterReceive() external {
        require(msg.sender == address(escrow), "L2: only escrow");
        canRequest = true;
    }

    function afterTransfer() external onlyRole(STRATEGIST_ROLE) {
        canTransfer = true;
    }


    /*//////////////////////////////////////////////////////////////
                             TVL ESTIMATION
    //////////////////////////////////////////////////////////////*/
    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset() + aToken.balanceOf(address(this));
    }
}
