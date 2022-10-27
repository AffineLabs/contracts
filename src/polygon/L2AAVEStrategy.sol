// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

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
    function _afterInvest(uint256 amount) internal override {
        lendingPool.deposit(address(asset), amount, address(this), 0);
    }

    /**
     * DIVESTMENT
     *
     */
    function _divest(uint256 assets) internal override returns (uint256) {
        uint256 currAssets = balanceOfAsset();
        uint256 withdrawAmount = currAssets >= assets ? 0 : assets - currAssets;
        lendingPool.withdraw(address(asset), withdrawAmount, address(this));

        uint256 amountToSend = Math.min(assets, balanceOfAsset());
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
