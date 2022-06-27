import { ethers } from "hardhat";
import hre from "hardhat";
import { L2Vault__factory, MintableStrategy__factory } from "../../typechain";
import { readAddressBook } from "../utils/export";

// Mint 0.03% (3 BPS) in the strategy every day
// This comes out to an APY of about 12%
async function mintUSDC() {
  const polygonNetwork = process.env.POLYGON_NETWORK || "polygon-mumbai-fork";
  hre.changeNetwork(polygonNetwork);

  const [signer] = await ethers.getSigners();

  //  Get address of strategies, from address book stable version
  const addrBook = await readAddressBook();

  // TODO: The strategy was deployed independently and didn't make it into the addressbook.
  // Once we deploy a version newer than v0.0.10-erc4626.0 we can use the line below
  // const strategyAddr: string = addrBook.PolygonMintableStrategy.address;
  const strategyAddr = "0x439D788657BB8C50B522B1f408C5e767e9FEa841";
  const strategy = MintableStrategy__factory.connect(strategyAddr, signer);
  // Figure out how much tvl the vault has
  const l2Vault = L2Vault__factory.connect(await strategy.vault(), signer);
  const vaultTVL = await l2Vault.totalAssets();

  console.log({ vaultTVL });

  //  Mint a gain equal to 3 bps of vaul tvl
  const gain = vaultTVL.mul(3).div(10_000);
  console.log({ gain });
  const res = await strategy.gainAsset(gain);
  await res.wait();
  console.log("gain completed");

  console.log("calling harvest");
  console.log("deployer has role: ", await l2Vault.hasRole(await l2Vault.harvesterRole(), await signer.getAddress()));
  console.log("strategy tvl: ", await strategy.totalLockedValue());

  console.log("current totalStrategyHoldings: ", await l2Vault.totalStrategyHoldings());

  // call harvest on the vault
  const harvestRes = await l2Vault.harvest([strategyAddr]);
  await harvestRes.wait();
  console.log("vault locked profit: ", [await l2Vault.lockedProfit(), await l2Vault.maxLockedProfit()]);
  console.log("new totalStrategyHoldings: ", await l2Vault.totalStrategyHoldings());
}

mintUSDC()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
