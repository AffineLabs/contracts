// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { IHevm } from "./IHevm.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { L1Vault } from "../eth-contracts/L1Vault.sol";
import { Create2Deployer } from "./Create2Deployer.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { L1CompoundStrategy, ICToken, IComptroller } from "../eth-contracts/L1CompoundStrategy.sol";

contract L1CompoundStratTestFork is DSTest {
    ERC20 comp_token = ERC20(0xe16C7165C8FeA64069802aE4c4c9C320783f2b6e);
    IComptroller comptroller = IComptroller(0x627EA49279FD0dE89186A58b8758aD02B6Be2867);
    ICToken cusdc = ICToken(0xCEC4a43eBB02f9B80916F1c718338169d6d5C1F0);
    ERC20 usdc = ERC20(0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C);
    // 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D is a cheat address of hevm which allows manipulating time
    // See https://github.com/dapphub/dapptools/pull/71
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    IWormhole wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);
    ERC20 weth = ERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    IRootChainManager root_chain_manager = IRootChainManager(0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74);
    address erc20_predicate = 0xdD6596F2029e6233DEFfaCa316e6A95217d4Dc34;
    address uniswap_router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    uint256 usdc_balances_storage_slot = 0;

    L1Vault vault;
    Create2Deployer create2Deployer;
    L1CompoundStrategy strategy;

    // constants
    uint256 one_usdc = 1e6;
    uint256 half_usdc = one_usdc / 2;

    function setUp() public {
        create2Deployer = new Create2Deployer();
        vault = new L1Vault(
            address(this), // governance
            usdc, // token -> Goerli USDC that Compund takes in
            wormhole, // wormhole
            create2Deployer, // create2deployer (needs to be a real contract)
            root_chain_manager,
            erc20_predicate
        );
        strategy = new L1CompoundStrategy(
            address(vault),
            address(cusdc), // aave adress provider registry
            address(comptroller), // dummy incentives controller
            uniswap_router, // sushiswap router on goerli
            address(comp_token), // reward token -> comp token
            address(weth) // wrapped eth address
        );
    }

    function testStrategyHarvestSuccessfully() public {
        // Give the Vault 1 usdc
        hevm.store(address(usdc), keccak256(abi.encode(address(vault), usdc_balances_storage_slot)), bytes32(one_usdc));

        // This contract is the governance address so this will work
        vault.addStrategy(address(strategy), 5000, 0, type(uint256).max);

        strategy.harvest();

        // After calling harvest for the first time, we take 5000/10000 percentage of the vaults assets
        assertEq(usdc.balanceOf(address(vault)), half_usdc);
        assertEq(vault.totalDebt(), half_usdc);

        // Strategy deposits all of usdc into Compound
        assertInRange(strategy.cToken().balanceOfUnderlying(address(strategy)), half_usdc - 1, half_usdc);

        (, , , , , uint256 totalDebt, , ) = vault.strategies(address(strategy));
        assertEq(totalDebt, half_usdc);
    }

    // TODO: Add more unit tests.
}
