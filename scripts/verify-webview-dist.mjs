import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const distIndex = path.join(rootDir, "WebViewApp", "dist", "index.html");
const relDistIndex = path.relative(rootDir, distIndex).replaceAll(path.sep, "/");

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

function isTracked(relativePath) {
  try {
    execFileSync("git", ["ls-files", "--error-unmatch", relativePath], {
      cwd: rootDir,
      stdio: "ignore"
    });
    return true;
  } catch {
    return false;
  }
}

if (!existsSync(distIndex)) {
  fail(`Missing ${relDistIndex}. Run npm.cmd run build from WebViewApp.`);
  process.exit();
}

const html = readFileSync(distIndex, "utf8");
const refs = Array.from(html.matchAll(/\b(?:src|href)="\.\/([^"]+)"/g), (match) => match[1]);

if (refs.length === 0) {
  fail(`${relDistIndex} does not reference any local built assets.`);
}

for (const ref of refs) {
  const assetPath = path.join(rootDir, "WebViewApp", "dist", ref);
  const relativePath = path.relative(rootDir, assetPath).replaceAll(path.sep, "/");
  if (!existsSync(assetPath)) {
    fail(`${relDistIndex} references missing asset ${relativePath}.`);
    continue;
  }
  if (!isTracked(relativePath)) {
    fail(`${relativePath} exists but is not tracked by git. Stage rebuilt WebViewApp/dist assets before running this release check.`);
  }
}

if (process.exitCode) {
  process.exit();
}

console.log(`Verified ${refs.length} WebView dist asset reference(s).`);
