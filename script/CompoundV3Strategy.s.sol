// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Script, console2} from "forge-std/Script.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {CompoundV3Strategy, IComet, IRewards, IUniswapV2Router02} from "src/strategies/CompoundV3Strategy.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address cTokenAddr = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        IRewards rewards = IRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);
        ERC20 comp = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;

        AffineVault vault = AffineVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9);
        CompoundV3Strategy strategy = new CompoundV3Strategy({
            _vault: vault,
            _cToken: IComet(cTokenAddr),
            _rewards: rewards,
            _comp: comp,
            _weth: weth,
            _router: router,
            strategists: strategists
        });
        require(strategy.vault() == vault);
    }
}
