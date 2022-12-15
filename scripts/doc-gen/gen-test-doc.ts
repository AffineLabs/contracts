#!/usr/bin/env node

import { docgen } from "solidity-docgen";
import { readdir, readFile } from "node:fs/promises";
import path from "path";
import { SourceUnit } from "solidity-ast";
import { SolcOutput } from "solidity-ast/solc";

type SolcOutputUnit = {
  ast: SourceUnit;
  id: number;
};

const main = async () => {
  const outputDir = "./out";
  const solcOutput: SolcOutput = { sources: {} };
  const dirs = await readdir(outputDir);
  for (let dirName of dirs) {
    if (!dirName.endsWith(".t.sol")) continue;
    const dirFiles = await readdir(path.join(outputDir, dirName), { withFileTypes: true });
    for (const f of dirFiles) {
      if (f.isDirectory()) continue;
      const content = JSON.parse((await readFile(path.join(outputDir, dirName, f.name))).toString()) as SolcOutputUnit;
      const fName = f.name.replace(".json", ".sol");
      solcOutput.sources[fName] = content;
    }
  }
  await docgen([{ input: { sources: {} }, output: solcOutput }], {
    sourcesDir: "src/test",
    outputDir: "docs/test",
    templates: "scripts/doc-gen",
  });
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
