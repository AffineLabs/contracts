async function main() {
  const [governance, tokenOwner, strategist] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", [
    governance.address,
    tokenOwner.address,
    strategist.address,
  ]);

  // TestToken deployed by `tokenOwner`.
  const tokenFactory = await ethers.getContractFactory("TestToken", tokenOwner);
  const token = await tokenFactory.deploy(ethers.utils.parseUnits("100000", 6));
  await token.deployTransaction.wait();
  console.log("token: ", token.address);

  // Vault deployed by governance
  const vaultFactory = await ethers.getContractFactory("L2Vault", governance);
  const vault = await vaultFactory.deploy(governance.address, token.address);
  await vault.deployTransaction.wait();
  console.log("vault: ", vault.address);

  // Deploy strategy
  const stratFactory = await ethers.getContractFactory(
    "TestStrategy",
    strategist
  );
  const strategy = await stratFactory.deploy(vault.address);
  await strategy.deployTransaction.wait();
  console.log("strategy: ", strategy.address);

  // Add strategy, with 9000 (90%) debtRatio, 0 minDebtPerHarvest, and maxDebtPerHarvst of totalSupply of token
  const addTx = await vault
    .connect(governance)
    .addStrategy(
      strategy.address,
      9000,
      0,
      ethers.utils.parseUnits("100000", 6)
    );
  await addTx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
