require("@nomiclabs/hardhat-ethers");

require("dotenv").config();
const MNEMONIC = process.env.DEPLOYER_SEED || "";
const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;

task("gain", "Causes strategy to gain/lose")
  .addParam("strategy", "The strategy address")
  .addFlag("loss", "If present, report a gain, else report a loss")
  .setAction(async ({ strategy: stratAddr, loss }) => {
    const [, , strategist] = await ethers.getSigners();

    // Deploy strategy
    const stratFactory = await ethers.getContractFactory(
      "TestStrategy",
      strategist
    );
    const strategy = stratFactory.attach(ethers.utils.getAddress(stratAddr));

    // Harvest gain or loss
    const amount = ethers.utils.parseUnits("10", 6);
    if (!loss) {
      console.log("gaining");
      const tx = await strategy.harvestGain(amount);
      await tx.wait();
    } else {
      const tx = strategy.harvestLoss(amount);
      await tx.wait();
    }
  });

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.9",
  networks: {
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      accounts: {
        count: 10,
        initialIndex: 0,
        mnemonic: MNEMONIC,
        path: "m/44'/60'/0'/0",
      },
      chainId: 42,
    },
  },
};
