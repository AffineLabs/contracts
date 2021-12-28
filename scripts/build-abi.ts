import { resolve } from "path";
import { readFileSync } from "fs";
import { writeFile } from "fs/promises";
import glob from "glob";

type artifactInfo = {
  [name: string]: dappArtifact;
};
interface dappArtifact {
  abi: any;
  evm: { bytecode: string };
}
async function buildAbi() {
  const artifactDir = resolve(__dirname, "../out");
  const path = `${artifactDir}/dapp.sol.json`;
  const raw = JSON.parse(readFileSync(path, "utf-8"));

  // Get all sources
  const sources = glob.sync(`src/**/*.sol`, {});
  const res = sources.map(src => {
    // This is a map of contract names found in the file to the compiler output for that contract,
    // an `artifact` containing `abi`, `evm`, etc. properties
    const contractToArtifact: artifactInfo = raw.contracts[src];
    const writes = Object.entries(contractToArtifact).map(([contractName, artifact]) => {
      const path = resolve(__dirname, "../abi", `${contractName}.abi`);
      return writeFile(path, JSON.stringify(artifact.abi));
    });
    return Promise.all(writes);
  });
  await Promise.all(res);
}
buildAbi()
  .then(() => {
    console.log("Abi files are in /abi");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
