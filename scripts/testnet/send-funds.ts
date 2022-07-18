import { ethers } from "hardhat";
import hre from "hardhat";
import { L2Vault__factory, MintableToken__factory, TwoAssetBasket__factory } from "../../typechain";
import { readAddressBook } from "../utils/export";

// Send some usdc and alpLarge and alpSave to some test users
async function sendFunds() {
  const polygonNetwork = process.env.POLYGON_NETWORK || "polygon-mumbai-fork";
  hre.changeNetwork(polygonNetwork);
  const [signer] = await ethers.getSigners();

  // We need the address book to find the current addresses
  const addrBook = await readAddressBook();

  const l2Vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, signer);
  const alpLarge = TwoAssetBasket__factory.connect(addrBook.PolygonBtcEthVault.address, signer);
  const usdc = MintableToken__factory.connect(addrBook.PolygonUSDC.address, signer);

  const oneUsdc = ethers.BigNumber.from(10).pow(6);
  const users = [
    "0x2bB37CE5B3E72069Ca4415E53666384891a0F555",
    "0x35A21ED909836f3b1dA08533FaC618Db0F245312",
    "0x423a21CbDB76cEb5EC997C6d3aEe1277512902eC",
    "0x2163E90E35E96363676A2D0f04eC2bef4E370D13",
  ];
  for (const user of users) {
    // Mint 10,000 usdc
    let tx = await usdc.mint(user, oneUsdc.mul(10_000));
    await tx.wait();

    // Buy $5000 alpLarge
    tx = await l2Vault.deposit(oneUsdc.mul(5_000), user);
    await tx.wait();

    // Buy $5000 alpSave
    tx = await alpLarge.deposit(oneUsdc.mul(5_000), user);
    await tx.wait();
    console.log(
      "user bals: ",
      await Promise.all([usdc.balanceOf(user), l2Vault.balanceOf(user), alpLarge.balanceOf(user)]),
    );
  }
}

sendFunds()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
