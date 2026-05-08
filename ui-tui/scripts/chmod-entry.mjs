import { chmod } from "node:fs/promises";
import { resolve } from "node:path";

if (process.platform !== "win32") {
  await chmod(resolve("dist/entry.js"), 0o755);
}
