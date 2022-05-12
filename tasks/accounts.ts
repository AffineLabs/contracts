import { task } from "hardhat/config";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});

import { ethers } from "ethers";

task("unblock", "Unblock tx", async (args, hre) => {
    const [deployer] = await hre.ethers.getSigners();
    const tx = await deployer.sendTransaction({
        to: deployer.address,
        value: ethers.utils.parseUnits("1", "gwei"),
        nonce: 329,
        gasPrice: ethers.utils.parseUnits("2", "gwei"),
    });
    console.log("Our Tx:\n", tx);
    await tx.wait();
});
