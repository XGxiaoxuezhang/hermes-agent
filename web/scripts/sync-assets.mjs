import { access, cp, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(webRoot, "..");

async function pathExists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function resolveUiDist() {
  const candidates = [
    resolve(webRoot, "node_modules/@nous-research/ui/dist"),
    resolve(repoRoot, "node_modules/@nous-research/ui/dist"),
  ];

  for (const candidate of candidates) {
    if (await pathExists(candidate)) {
      return candidate;
    }
  }

  throw new Error(
    `Could not find @nous-research/ui dist. Checked: ${candidates.join(", ")}`,
  );
}

const uiDist = await resolveUiDist();

const copies = [
  {
    from: resolve(uiDist, "fonts"),
    to: "public/fonts",
  },
  {
    from: resolve(uiDist, "assets"),
    to: "public/ds-assets",
  },
];

for (const { from, to } of copies) {
  const source = from;
  const target = resolve(webRoot, to);

  await rm(target, { recursive: true, force: true });
  await cp(source, target, { recursive: true });
  console.log(`synced ${source} -> ${to}`);
}
