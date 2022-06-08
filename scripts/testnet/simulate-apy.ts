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
  const strategyAddr: string = addrBook.PolygonMintableStrategy.address;
  const strategy = MintableStrategy__factory.connect(strategyAddr, signer);
  // Figure out how much tvl the vault has
  const l2Vault = L2Vault__factory.connect(await strategy.vault(), signer);
  // TODO: run a release and change this to `totalAssets`
  const vaultTVL = await l2Vault.vaultTVL();

  console.log({ vaultTVL });

  //  Mint a gain equal to 3 bps of vaul tvl
  const gain = vaultTVL.mul(3).div(10_000);
  console.log({ gain });
  await strategy.gainAsset(gain);
  // call harvest on the vault
  await l2Vault.harvest([strategyAddr]);
}

mintUSDC()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
