async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const AlpUSDC = await ethers.getContractFactory("alpUSDC");
  const alpUSDC = await AlpUSDC.deploy();
  await alpUSDC.deployTransaction.wait();

  const Vault = await ethers.getContractFactory("Vault");
  const vault = await Vault.deploy(alpUSDC.address);
  await vault.deployTransaction.wait();

  // Deployer must give vault burning and minting roles
  const mintRole = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("MINTER_ROLE")
  );
  const burnRole = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("BURNER_ROLE")
  );
  // TODO: Figure out a way to not have to wait for the first grantTx to be mined before sending the second
  const grantTx1 = await alpUSDC.grantRole(mintRole, vault.address);
  await grantTx1.wait();
  const grantTx2 = await alpUSDC.grantRole(burnRole, vault.address);
  await grantTx2.wait();

  const AlpRelayRecipient = await ethers.getContractFactory(
    "AlpRelayRecipient"
  );
  const alpRelayRecipient = await AlpRelayRecipient.deploy(
    "0xF82986F574803dfFd9609BE8b9c7B92f63a1410E",
    vault.address
  );
  await alpRelayRecipient.deployTransaction.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
