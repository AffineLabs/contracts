// Example run:  npx hardhat --network eth-goerli unblock --nonce 408 --price 2
import { task } from "hardhat/config";
import { ethers } from "ethers";

task("unblock", "Unblock tx")
  .addParam("nonce", "Nonce of the tx that we are trying to unblock")
  .addParam("price", "Gas price in Gwei")
  .setAction(async ({nonce, price}, hre) => {
    const [deployer] = await hre.ethers.getSigners();
    const tx = await deployer.sendTransaction({
        to: deployer.address,
        nonce: parseInt(nonce),
        gasPrice: ethers.utils.parseUnits(price, "gwei"),
    });
    console.log("Replacement Tx:\n", tx);
    await tx.wait();
});
