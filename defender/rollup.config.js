import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";
import typescript from "@rollup/plugin-typescript";
import json from "@rollup/plugin-json";
// Need this to bundle @certusone/wormhole-sdk dependency
import wasm from "@rollup/plugin-wasm";
import builtins from "builtin-modules";

export default {
  input: "index.ts",
  output: {
    file: "dist/index.js",
    format: "cjs",
  },
  plugins: [resolve({ preferBuiltins: true }), commonjs(), json({ compact: true }), typescript(), wasm()],
  external: [...builtins, "ethers", "axios"],
};
