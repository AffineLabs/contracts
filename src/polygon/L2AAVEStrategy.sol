// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    ILendingPoolAddressesProviderRegistry, ILendingPoolAddressesProvider, ILendingPool
} from "../interfaces/aave.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

contract L2AAVEStrategy is BaseStrategy {
    using SafeTransferLib for ERC20;

    /// @notice The lending pool. We'll call deposit, withdraw, etc. on this.
    ILendingPool public immutable lendingPool;
    // Corresponding AAVE asset (USDC -> aUSDC)
    ERC20 public immutable aToken;

    constructor(BaseVault _vault, address _registry) BaseStrategy(_vault) {
        address[] memory providers = ILendingPoolAddressesProviderRegistry(_registry).getAddressesProvidersList();
        lendingPool = ILendingPool(ILendingPoolAddressesProvider(providers[providers.length - 1]).getLendingPool());
        aToken = ERC20(lendingPool.getReserveData(address(asset)).aTokenAddress);

        // We can mint/burn aTokens
        asset.safeApprove(address(lendingPool), type(uint256).max);
        aToken.safeApprove(address(lendingPool), type(uint256).max);
    }

    /**
     * INVESTMENT
     *
     */
    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        lendingPool.deposit(address(asset), amount, address(this), 0);
    }

    /**
     * DIVESTMENT
     *
     */
    function divest(uint256 amount) external override onlyVault returns (uint256) {
        uint256 currAssets = balanceOfAsset();
        uint256 withdrawAmount = currAssets >= amount ? 0 : amount - currAssets;
        lendingPool.withdraw(address(asset), withdrawAmount, address(this));

        uint256 amountToSend = Math.min(amount, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    /**
     * TVL ESTIMATION
     *
     */
    function totalLockedValue() public view override returns (uint256) {
        return balanceOfAsset() + aToken.balanceOf(address(this));
    }
}
