// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { Staging } from "../Staging.sol";
import { ICreate2Deployer } from "../interfaces/ICreate2Deployer.sol";

contract L2Vault is BaseVault {
    // TVL of L1 denominated in `token` (e.g. USDC). This value will be updated by oracle.
    uint256 public L1TotalLockedValue;

    // Represents the amount of tvl (in `token`) that should exist on L1 and L2
    // E.g. if layer1 == 1 and layer2 == 2 then 1/3 of the TVL should be on L1
    struct LayerBalanceRatios {
        uint256 layer1;
        uint256 layer2;
    }
    LayerBalanceRatios public layerRatios;

    /////// Cross chain rebalancing

    // Whether we can send or receive money from L1
    bool public canTransferToL1 = true;
    bool public canRequestFromL1 = true;

    event SendToL1(uint256 amount);
    event ReceiveFromL1(uint256 amount);

    constructor(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        ICreate2Deployer create2Deployer,
        uint256 L1Ratio,
        uint256 L2Ratio
    ) BaseVault(_governance, _token, _wormhole, create2Deployer) {
        layerRatios = LayerBalanceRatios({ layer1: L1Ratio, layer2: L2Ratio });
    }

    // We don't need to check if user == msg.sender()
    // So long as this conract can transfer usdc from the given user, everything is fine
    function deposit(address user, uint256 amountToken) external {
        // mint
        _issueSharesForAmount(user, amountToken);

        // transfer usdc to this contract
        token.transferFrom(user, address(this), amountToken);
    }

    function _issueSharesForAmount(address user, uint256 amountToken) internal {
        uint256 numShares;
        uint256 totalTokens = totalSupply;
        if (totalTokens == 0) {
            numShares = amountToken;
        } else {
            numShares = (amountToken * totalTokens) / globalTVL();
        }
        _mint(user, numShares);
    }

    // TVL is denominated in `token`.
    function globalTVL() public view returns (uint256) {
        return vaultTVL() + L1TotalLockedValue;
    }

    // TODO: handle access control, re-entrancy
    function withdraw(address user, uint256 shares) external {
        require(shares <= balanceOf[user], "Cannot burn more shares than owned");

        uint256 valueOfShares = _getShareValue(shares);

        // TODO: handle case where the user is trying to withdraw more value than actually exists in the vault
        if (valueOfShares > token.balanceOf(address(this))) {}

        // burn
        _burn(user, shares);

        // transfer usdc out
        token.transfer(user, valueOfShares);
    }

    function _getShareValue(uint256 shares) internal view returns (uint256) {
        // The price of the vault share (e.g. alpSave).
        // This is a ratio of share/token, i.e. the numbers of shares for single wei of the input token

        uint256 totalShares = totalSupply;
        if (totalShares == 0) {
            return shares;
        } else {
            return shares * (globalTVL() / totalShares);
        }
    }

    function receiveTVL(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);

        // TODO: check chain ID, emitter address
        // Get tvl from payload
        (uint256 tvl, bool received) = abi.decode(vm.payload, (uint256, bool));

        // If L1 has received the last transfer we sent it, unlock the L2->L1 bridge
        if (received && !canTransferToL1) canTransferToL1 = true;

        // If L1 is sending us money (!canRequestFromL1), the TVL its sending could be wrong
        if (canRequestFromL1) L1TotalLockedValue = tvl;

        // Only rebalance if all cross chain transfers have been settled.
        // If the L1 vault is sending money (!canRequestFromL1), then its TVL could be wrong. Also
        // we don't to accidentally request money again. If (!canTransferToL1), we don't want to accidentally
        // send money when one transfer to L1 is already in progress
        if (!canTransferToL1 || !canRequestFromL1) return;

        (bool invest, uint256 delta) = _computeRebalance();
        // if (delta < 100_000 * 10 ** decimals()) return;
        // TODO: use the condition above eventually, this is just for testing
        if (delta == 0) return;

        _L1L2Rebalance(invest, delta);
    }

    function _computeRebalance() internal view returns (bool, uint256) {
        uint256 numSlices = layerRatios.layer1 + layerRatios.layer2;
        uint256 L1IdealAmount = (layerRatios.layer1 * globalTVL()) / numSlices;

        bool invest;
        uint256 delta;
        if (L1IdealAmount >= L1TotalLockedValue) {
            invest = true;
            delta = L1IdealAmount - L1TotalLockedValue;
        } else {
            delta = L1TotalLockedValue - L1IdealAmount;
        }
        return (invest, delta);
    }

    function _L1L2Rebalance(bool invest, uint256 amount) internal {
        if (invest) {
            // Increase balance of `token` to `delta` by withdrawing from strategies.
            // Then transfer `amount` of `token` to L1.
            _liquidate(amount);
            uint256 amountToSend = Math.min(token.balanceOf(address(this)), amount);
            _transferToL1(amountToSend);
        } else {
            // Send message to L1 telling us how much should be transferred to this vault
            _divestFromL1(amount);
        }
    }

    // TODO: liquidate properly
    function _transferToL1(uint256 amount) internal {
        // Send token
        token.transfer(staging, amount);
        Staging(staging).l2Withdraw(amount);
        emit SendToL1(amount);

        // Update bridge state and L1 TVL
        // It's important to update this number now so that globalTVL() returns a smaller number
        canTransferToL1 = false;
        L1TotalLockedValue += amount;

        // Let L1 know how much money we sent
        uint64 sequence = wormhole.nextSequence(address(this));
        bytes memory payload = abi.encodePacked(amount);
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function _divestFromL1(uint256 amount) internal {
        // TODO: make wormhole address, consistencyLevel configurable
        bytes memory payload = abi.encodePacked(amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage(uint32(sequence), payload, 4);
        canRequestFromL1 = false;
    }

    function afterReceive(uint256 amount) external {
        require(msg.sender == staging, "Only L2 staging.");
        L1TotalLockedValue -= amount;
        canRequestFromL1 = true;
        emit ReceiveFromL1(amount);
    }
}
