import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

chai.use(solidity);
const { expect } = chai;

describe("I/O", async () => {
  it("Can deposit and withdraw", async () => {
    const [governance, user]: Array<SignerWithAddress> = await ethers.getSigners();
    
    const contractRegistryFactory = await ethers.getContractFactory("ContractRegistry", user);
    const contractRegistry = await contractRegistryFactory.deploy();

    const tokenFactory = await ethers.getContractFactory("TestMintable", user);
    const token = await tokenFactory.deploy(ethers.utils.parseUnits("100", 6));

    const vaultFactory = await ethers.getContractFactory("L2Vault", governance);
    const vault = await vaultFactory.deploy(governance.address, token.address, 1, 1, contractRegistry.address);

    await token.connect(user).approve(vault.address, ethers.utils.parseUnits("100", 6));
    await vault.connect(user).deposit(user.address, ethers.utils.parseUnits("5", 6));

    // user should get as many shares as usdc deposited
    expect(await vault.balanceOf(user.address)).to.equal(ethers.utils.parseUnits("5", 6));
    // user's balance went down by 5
    expect(await token.balanceOf(user.address)).to.equal(ethers.utils.parseUnits("95", 6));

    // withdrawing 1 share gets one usdc
    await vault.connect(user).withdraw(user.address, ethers.utils.parseUnits("1", 6));
    expect(await vault.balanceOf(user.address)).to.equal(ethers.utils.parseUnits("4", 6));
    expect(await token.balanceOf(user.address)).to.equal(ethers.utils.parseUnits("96", 6));

    // The amount of shares I get is determined by numToken * (totalshares/totaltokens)
    // Vault now has 8 usdc, but only 4 shares. So if I put in 2 usdc, I should get one more share
    await token.connect(user).transfer(vault.address, ethers.utils.parseUnits("4", 6));
    await vault.connect(user).deposit(user.address, ethers.utils.parseUnits("2", 6));
    expect(await vault.balanceOf(user.address)).to.equal(ethers.utils.parseUnits("5", 6));
  });
});

describe("reporting", () => {});

describe("Add and remove strategy", () => {});

describe("Update debt ratios", () => {});
