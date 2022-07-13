import { ethers } from "hardhat";
import hre from "hardhat";
import { L2Vault__factory, MintableToken__factory } from "../../typechain";
import { readAddressBook } from "../utils/export";

// Mint 0.03% (3 BPS) in the strategy every day
// This comes out to an APY of about 12%
async function mintUSDC() {
  const polygonNetwork = process.env.POLYGON_NETWORK || "polygon-mumbai-fork";
  hre.changeNetwork(polygonNetwork);

  const [signer] = await ethers.getSigners();

  // We need the address book to find the current addresses
  const addrBook = await readAddressBook();

  // Figure out how much tvl the vault has
  const l2Vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, signer);
  const vaultTVL = await l2Vault.totalAssets();

  console.log({ vaultTVL });

  //  Mint a gain equal to 3 bps of vaul tvl
  const gain = vaultTVL.mul(3).div(10_000);
  console.log({ gain });

  const mintableUsdc = MintableToken__factory.connect(addrBook.PolygonUSDC.address, signer);
  const res = await mintableUsdc.mint(l2Vault.address, gain);
  await res.wait();
  console.log("gain completed");
  const newVaultTVL = await l2Vault.totalAssets();
  console.log({ newVaultTVL });
}

mintUSDC()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
