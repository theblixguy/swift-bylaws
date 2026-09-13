import { build } from "esbuild";

await build({
  entryPoints: ["src/extension.ts"],
  outfile: "out/extension.js",
  bundle: true,
  external: ["vscode"],
  format: "cjs",
  minify: true,
  platform: "node",
  target: "node24",
  sourcemap: true,
});
