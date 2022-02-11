// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { DSTestPlus } from "./TestPlus.sol";
import { IHevm } from "./IHevm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { L1Vault } from "../eth-contracts/L1Vault.sol";
import { Create2Deployer } from "./Create2Deployer.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { IExchangeRateFeeder } from "../interfaces/anchor/IExchangeRateFeeder.sol";
import { IConversionPool } from "../interfaces/anchor/IConversionPool.sol";
import { L1AnchorStrategy } from "../eth-contracts/L1AnchorStrategy.sol";

contract EthAnchorStratTestFork is DSTestPlus {
    IERC20 aToken = IERC20(0xFff8fb0C13314c90805a808F48c7DFF37e95Eb16);
    IConversionPool usdcConversionPool = IConversionPool(0x92E68C8C24a0267fa962470618d2ffd21f9b6a95);
    IExchangeRateFeeder exchangeRateFeeder = IExchangeRateFeeder(0x79E0d9bD65196Ead00EE75aB78733B8489E8C1fA);
    ERC20 usdc = ERC20(0xE015FD30cCe08Bc10344D934bdb2292B1eC4BBBD);
    // 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D is a cheat address of hevm which allows manipulating time
    // See https://github.com/dapphub/dapptools/pull/71
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    uint256 usdcBalancesStorageSlot = 6;

    L1Vault vault;
    Create2Deployer create2Deployer;
    L1AnchorStrategy strategy;

    // constants
    uint256 hundredUSDC = 1e8;
    uint256 fiftyUSDC = hundredUSDC / 2;

    function setUp() public {
        create2Deployer = new Create2Deployer();
        vault = new L1Vault();
        vault.initialize(
            address(this), // governance
            usdc, // token -> Ropsten USDC that Anchor takes in
            IWormhole(address(0)), // wormhole
            create2Deployer, // create2deployer (needs to be a real contract)
            IRootChainManager(address(0)), // Polygon root chain manager
            address(0) // Polygon ERC20 predicate
        );
        strategy = new L1AnchorStrategy(address(vault), aToken, usdcConversionPool, exchangeRateFeeder);
    }

    function testStrategyHarvestSuccessfully() public {
        // Give the Vault 1 usdc
        hevm.store(address(usdc), keccak256(abi.encode(address(vault), usdcBalancesStorageSlot)), bytes32(hundredUSDC));
        // This contract is the governance address so this will work
        vault.addStrategy(address(strategy), 5000, 0, type(uint256).max);

        // Make sure strategy deposits fifty USDC to Eth Anchor during harvest.
        bytes4 funcSelector = bytes4(keccak256("deposit(uint256)"));
        bytes memory expectedData = abi.encodeWithSelector(funcSelector, fiftyUSDC);
        hevm.expectCall(address(usdcConversionPool), expectedData);

        strategy.harvest();

        // After calling harvest for the first time, we take 5000/10000 percentage of the vaults assets
        assertEq(usdc.balanceOf(address(vault)), fiftyUSDC);
        assertEq(vault.totalDebt(), fiftyUSDC);
        (, , , , , uint256 totalDebt, , ) = vault.strategies(address(strategy));
        assertEq(totalDebt, fiftyUSDC);
    }

    // TODO: Add more unit tests.
}
