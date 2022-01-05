import { ethers } from "ethers";
import hardhat from "hardhat";
import { readFileSync } from "fs";
import { resolve } from "path";
import glob from "glob";

export async function getContractFactory(contractName: string, signer?: ethers.Signer, buildType: string = "dapp") {
  const artifactDir = resolve(__dirname, "../../out");
  if (signer == undefined) {
    [signer] = await hardhat.ethers.getSigners();
  }

  let artifact;
  if (buildType == "forge") {
    const path = `${artifactDir}/${contractName}.sol/${contractName}.json`;
    artifact = JSON.parse(readFileSync(path, "utf-8"));
    return new ethers.ContractFactory(artifact.abi, artifact.bin);
  } else {
    const path = `${artifactDir}/dapp.sol.json`;
    // you need to know the contract path in order to find its abi/bytecode
    const raw = JSON.parse(readFileSync(path, "utf-8"));

    // NOTE: the cwd for this search is process.cwd() so this will only work when script is run from smart-contracts/
    const contractPath = glob.sync(`src/**/${contractName}.sol`, {})[0];
    artifact = raw.contracts[contractPath][contractName];
    return new ethers.ContractFactory(artifact.abi, artifact.evm.bytecode.object, signer);
  }
}
