// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { Staging } from "../Staging.sol";
import { Relayer } from "./Relayer.sol";
import { ICreate2Deployer } from "../interfaces/ICreate2Deployer.sol";

contract L2Vault is ERC20Upgradeable, UUPSUpgradeable, BaseVault {
    using SafeTransferLib for ERC20;

    // TVL of L1 denominated in `token` (e.g. USDC). This value will be updated by oracle.
    uint256 public L1TotalLockedValue;

    /////// Cross chain rebalancing

    // Represents the amount of tvl (in `token`) that should exist on L1 and L2
    // E.g. if layer1 == 1 and layer2 == 2 then 1/3 of the TVL should be on L1
    struct LayerBalanceRatios {
        uint256 layer1;
        uint256 layer2;
    }
    LayerBalanceRatios public layerRatios;

    // Whether we can send or receive money from L1
    bool public canTransferToL1;
    bool public canRequestFromL1;

    event SendToL1(uint256 amount);
    event ReceiveFromL1(uint256 amount);

    /////// Gasless transactions
    Relayer public relayer;

    ///// Fees
    // 2 percent management fee charged to vault per year
    uint256 public constant managementFee = 200;

    uint256 public withdrawalFee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        ICreate2Deployer create2Deployer,
        uint256 L1Ratio,
        uint256 L2Ratio,
        address trustedForwarder,
        uint256 _withdrawalFee
    ) public initializer {
        __ERC20_init("Alpine Save", "alpSave");
        __UUPSUpgradeable_init();
        BaseVault.init(_governance, _token, _wormhole, create2Deployer);
        layerRatios = LayerBalanceRatios({ layer1: L1Ratio, layer2: L2Ratio });
        canTransferToL1 = true;
        canRequestFromL1 = true;
        relayer = new Relayer(trustedForwarder, address(this));
        withdrawalFee = _withdrawalFee;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    function decimals() public view override returns (uint8) {
        return token.decimals();
    }

    function _deposit(address user, uint256 amountToken) internal {
        // mint
        uint256 numShares = sharesFromTokens(amountToken);
        _mint(user, numShares);

        // Get usdc
        token.safeTransferFrom(user, address(this), amountToken);
    }

    function deposit(uint256 amountToken) external {
        _deposit(msg.sender, amountToken);
    }

    // To be called only by the relayer.
    function depositGasLess(address user, uint256 amountToken) external {
        require(msg.sender == address(relayer), "Only relayer");
        _deposit(user, amountToken);
    }

    function sharesFromTokens(uint256 amountToken) public view returns (uint256) {
        // Amount of shares you get for a given amount of tokens
        uint256 numShares;
        uint256 totalTokens = totalSupply();
        if (totalTokens == 0) {
            numShares = amountToken;
        } else {
            numShares = (amountToken * totalTokens) / globalTVL();
        }
        return numShares;
    }

    // TVL is denominated in `token`.
    function globalTVL() public view returns (uint256) {
        return vaultTVL() - lockedProfit() + L1TotalLockedValue;
    }

    function _withdraw(address user, uint256 shares) internal {
        uint256 valueOfShares = tokensFromShares(shares);

        // TODO: handle case where the user is trying to withdraw more value than actually exists in the vault
        if (valueOfShares > token.balanceOf(address(this))) {}

        // burn
        _burn(user, shares);

        uint256 userTokens = _applyWithdrawalFee(valueOfShares);

        // transfer usdc out
        token.safeTransfer(user, userTokens);
    }

    function withdraw(uint256 shares) external {
        _withdraw(msg.sender, shares);
    }

    function withdrawGasLess(address user, uint256 shares) external {
        require(msg.sender == address(relayer), "Only relayer");
        _withdraw(user, shares);
    }

    function tokensFromShares(uint256 shares) public view returns (uint256) {
        // Amount of tokens you get for the given amount of shares.
        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            return shares;
        } else {
            return shares * (globalTVL() / totalShares);
        }
    }

    // Return number of tokens to be given to user after applying withdrawal fee
    function _applyWithdrawalFee(uint256 tokenAmount) internal returns (uint256) {
        uint256 feeAmount = (tokenAmount * withdrawalFee) / MAX_BPS;
        token.transfer(governance, feeAmount);
        return tokenAmount - feeAmount;
    }

    function setWithdrawalFee(uint256 newWithdrawalFee) external onlyGovernance {
        withdrawalFee = newWithdrawalFee;
    }

    function _assessFees() internal override {
        // duration / SECS_PER_YEAR * feebps / MAX_BPS * totalSupply
        uint256 duration = block.timestamp - lastReport;

        uint256 feesBps = (duration * managementFee) / SECS_PER_YEAR;
        uint256 numSharesToMint = (feesBps * totalSupply()) / MAX_BPS;

        if (numSharesToMint == 0) return;
        _mint(governance, numSharesToMint);
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
        token.safeTransfer(staging, amount);
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
