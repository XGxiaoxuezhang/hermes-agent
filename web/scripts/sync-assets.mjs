import { cp, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const copies = [
  {
    from: "node_modules/@nous-research/ui/dist/fonts",
    to: "public/fonts",
  },
  {
    from: "node_modules/@nous-research/ui/dist/assets",
    to: "public/ds-assets",
  },
];

for (const { from, to } of copies) {
  const source = resolve(webRoot, from);
  const target = resolve(webRoot, to);

  await rm(target, { recursive: true, force: true });
  await cp(source, target, { recursive: true });
  console.log(`synced ${from} -> ${to}`);
}
