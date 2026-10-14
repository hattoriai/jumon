// Runs the unit tests of the pure modules: each test/*.test.ts is bundled
// with esbuild into tmp/ and run with node's test runner.

import { readdirSync, mkdirSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { build } from "esbuild";

const out = `../tmp/assets-test-${process.pid}`;
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const only = process.argv.slice(2);
const files = readdirSync("test")
  .filter((name) => name.endsWith(".test.ts"))
  .filter((name) => only.length === 0 || only.some((part) => name.includes(part)));

await build({
  entryPoints: files.map((name) => `test/${name}`),
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node20",
  outdir: out,
  outExtension: { ".js": ".mjs" },
  logLevel: "warning",
});

const run = spawnSync(process.execPath, ["--test", ...files.map((name) => `${out}/${name.replace(/\.ts$/, ".mjs")}`)], {
  stdio: "inherit",
  env: { ...process.env, TZ: process.env.TZ ?? "America/Los_Angeles" },
});
rmSync(out, { recursive: true, force: true });
process.exit(run.status ?? 1);
