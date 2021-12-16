// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStrategy } from "../IStrategy.sol";
import { BaseVault } from "../BaseVault.sol";
import { L2BalancableVault } from "./L2BalancableVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";

interface IFxStateChildTunnel {
    function sendMessageToRoot(bytes memory message) external;
}

contract L2Vault is BaseVault, L2BalancableVault {
    event SendFundToL1(uint256 amount);
    event ReceiveFundFromL1(uint256 amount);

    // TVL of L1 denominated in `token` (e.g. USDC). This value will be updated by oracle.
    uint256 public L1TotalLockedValue;

    // Represents the amount of tvl (in `token`) that should exist on L1 and L2
    // E.g. if layer1 == 1 and layer2 == 2 then 1/3 of the TVL should be on L1
    struct LayerBalanceRatios {
        uint256 layer1;
        uint256 layer2;
    }
    LayerBalanceRatios layerRatios;

    constructor(
        address governance_,
        address token_,
        uint256 L1Ratio,
        uint256 L2Ratio,
        address wormhole_,
        address _l2ContractRegistryAddress
    ) BaseVault(governance_, token_, wormhole_) L2BalancableVault(_l2ContractRegistryAddress) {
        layerRatios = LayerBalanceRatios({ layer1: L1Ratio, layer2: L2Ratio });
    }

    // We don't need to check if user == msg.sender()
    // So long as this conract can transfer usdc from the given user, everything is fine
    function deposit(address user, uint256 amountToken) external {
        // mint
        _issueSharesForAmount(user, amountToken);

        // transfer usdc to this contract
        IERC20(token).transferFrom(user, address(this), amountToken);
    }

    function _issueSharesForAmount(address user, uint256 amountToken) internal {
        uint256 numShares;
        uint256 totalTokens = totalSupply();
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

    function setL1TVL(uint256 l1TVL) internal {
        L1TotalLockedValue = l1TVL;
    }

    // TODO: handle access control, re-entrancy
    function withdraw(address user, uint256 shares) external {
        require(shares <= balanceOf(user), "Cannot burn more shares than owned");

        uint256 valueOfShares = _getShareValue(shares);

        // TODO: handle case where the user is trying to withdraw more value than actually exists in the vault
        if (valueOfShares > IERC20(token).balanceOf(address(this))) {}

        // burn
        _burn(user, shares);

        // transfer usdc out
        IERC20(token).transfer(user, valueOfShares);
    }

    function _getShareValue(uint256 shares) internal view returns (uint256) {
        // The price of the vault share (e.g. alpSave).
        // This is a ratio of share/token, i.e. the numbers of shares for single wei of the input token

        uint256 totalShares = totalSupply();
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

        // get tvl from payload
        (uint256 tvl, uint256 blockNum) = abi.decode(vm.payload, (uint256, uint256));
        setL1TVL(tvl);
    }

    // Compute rebalance amount
    function L1L2Rebalance() external {
        require(
            msg.sender == l2ContractRegistry.getAddress("Defender"),
            "L2Vault[L1L2Rebalance]: Only defender should be able to initiate rebalance."
        );
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

        // if (delta < 100_000 * decimals()) return;

        if (invest) {
            // Increase balance of `token` to `delta` by withdrawing from strategies.
            // Then transfer `delta` of `token` to L1.
            _liquidate(delta);
            transferToL1(delta);
        } else {
            // send message to L1 telling us how much should be transferred to this vault
            divestFromL1(delta);
        }
    }

    function transferToL1(uint256 amount) internal {
        emit SendFundToL1(amount);
        _transferFundsToL1(amount);
    }

    function divestFromL1(uint256 amount) internal {
        emit ReceiveFundFromL1(amount);
        IFxStateChildTunnel(l2ContractRegistry.getAddress("L2FxTunnel")).sendMessageToRoot(abi.encodePacked(amount));
    }
}
