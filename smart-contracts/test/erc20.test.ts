import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Contract } from 'ethers';

chai.use(solidity);
const { expect } = chai;

describe("Token", () => {
  let tokenInstance: Contract;

  beforeEach(async () => {
    const tokenFactory =  await ethers.getContractFactory('TestToken');
    tokenInstance = await tokenFactory.deploy();
    expect(await tokenInstance.totalSupply()).to.eq(0);
  });

  describe("Mint", async () => {
    it("Should mint some tokens", async () => {
      const [_, user] = await ethers.getSigners();
      const toMint = ethers.utils.parseEther("1");

      await tokenInstance.mint(user.address, toMint);
      expect(await tokenInstance.totalSupply()).to.eq(toMint);
    });
  });

  describe("Transfer", async () => {
    it("Should transfer tokens between users", async () => {
      const [deployer, sender, receiver] = await ethers.getSigners();
      const deployerInstance = tokenInstance.connect(deployer);
      const toMint = ethers.utils.parseEther("1");

      await deployerInstance.mint(sender.address, toMint);
      expect(await deployerInstance.balanceOf(sender.address)).to.eq(toMint);

      const senderInstance = tokenInstance.connect(sender);
      const toSend = ethers.utils.parseEther("0.4");
      await senderInstance.transfer(receiver.address, toSend);

      expect(await senderInstance.balanceOf(receiver.address)).to.eq(toSend);
    });

    it("Should fail to transfer with low balance", async () => {
      const [deployer, sender, receiver] = await ethers.getSigners();
      const deployerInstance = tokenInstance.connect(deployer);
      const toMint = ethers.utils.parseEther("1");

      await deployerInstance.mint(sender.address, toMint);
      expect(await deployerInstance.balanceOf(sender.address)).to.eq(toMint);

      const senderInstance = tokenInstance.connect(sender);
      const toSend = ethers.utils.parseEther("1.1");

      // Notice await is on the expect
      await expect(senderInstance.transfer(receiver.address, toSend)).to.be.revertedWith(
        "transfer amount exceeds balance",
      );
    });
  });
});
