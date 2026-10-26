// Build and verify a complete site artifact before publication.
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

export function files(root, prefix = "") {
  return readdirSync(join(root, prefix), { withFileTypes: true }).flatMap(entry => {
    const path = join(prefix, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Symlink is not allowed: ${path}`);
    if (entry.isDirectory()) return files(root, path);
    if (!entry.isFile()) throw new Error(`Unsupported file: ${path}`);
    return [path];
  }).sort();
}
const digest = path => createHash("sha256").update(readFileSync(path)).digest("hex");
export function verify(root) {
  const manifest = JSON.parse(readFileSync(join(root, "artifact.json")));
  const actual = files(root).filter(path => path !== "artifact.json");
  const expected = Object.keys(manifest.files).sort();
  if (!actual.length || !expected.length || JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error("Artifact inventory changed");
  for (const path of actual) {
    if (digest(join(root, path)) !== manifest.files[path]) throw new Error(`Artifact checksum changed: ${path}`);
  }
  if (manifest.schema !== 1 || !manifest.video || !manifest.guides) throw new Error("Invalid artifact metadata");
  return manifest;
}
export function stage(repo, video, poster) {
  // The guide build must succeed before a staging artifact can be accepted.
  execFileSync("npm", ["ci", "--include=dev"], { cwd: join(repo, "site/guides"), stdio: "inherit" });
  execFileSync("npm", ["run", "build"], { cwd: join(repo, "site/guides"), stdio: "inherit" });
  const parent = join(repo, "build/site-stages");
  mkdirSync(parent, { recursive: true });
  const root = mkdtempSync(join(parent, "site-"));
  const assets = join(root, "assets");
  cpSync(join(repo, "site/public"), assets, { recursive: true });
  cpSync(join(repo, "site/guides/dist"), join(assets, "guides"), { recursive: true });
  mkdirSync(join(assets, "media"), { recursive: true });
  mkdirSync(join(assets, "fonts"), { recursive: true });
  const videoName = video.split("/").at(-1);
  const posterName = videoName.replace(/\.mp4$/, "") + "-poster." + poster.split(".").at(-1);
  cpSync(video, join(assets, "media", videoName));
  cpSync(poster, join(assets, "media", posterName));
  cpSync(join(repo, ".github/assets/nextshot-icon.png"), join(assets, "nextshot-icon.png"));
  cpSync(join(repo, "scripts/video/nextshot-onboarding/assets/fonts/Inter-latin.woff2"), join(assets, "fonts/Inter-latin.woff2"));
  cpSync(join(repo, "LICENSE"), join(assets, "LICENSE.txt"));
  const index = join(assets, "index.html");
  const html = readFileSync(index, "utf8").replaceAll("{{VIDEO}}", videoName).replaceAll("{{POSTER}}", posterName);
  if ((html.match(/{{[A-Z]+}}/g) || []).some(value => value !== "{{VERSION}}")) throw new Error("Unfilled homepage placeholder");
  writeFileSync(index, html);
  const assetFiles = files(assets);
  if (!assetFiles.includes("guides/index.html") || !assetFiles.some(path => path.startsWith("guides/pagefind/"))) throw new Error("Guide HTML or Pagefind is missing");
  for (const path of assetFiles) {
    if (statSync(join(assets, path)).size >= 25 * 1024 * 1024) throw new Error(`Static asset is 25 MiB or larger: ${path}`);
  }
  const sizes = assetFiles.filter(path => /\.(mp4|webm|mov)$/i.test(path)).map(path => `/${path}=${statSync(join(assets, path)).size}`).join(",");
  cpSync(join(repo, "site/src"), join(root, "src"), { recursive: true });
  const config = JSON.parse(readFileSync(join(repo, "site/wrangler.jsonc"), "utf8").replace(/^\s*\/\/.*$/gm, ""));
  config.assets.directory = "./assets";
  config.assets.not_found_handling = "404-page";
  config.vars = { ...config.vars, SIZES: sizes };
  writeFileSync(join(root, "wrangler.json"), JSON.stringify(config, null, 2) + "\n");
  const manifest = { schema: 1, created: new Date().toISOString(), commit: execFileSync("git", ["rev-parse", "HEAD"], { cwd: repo, encoding: "utf8" }).trim(), version: readFileSync(join(repo, "VERSION"), "utf8").trim(), video: videoName, poster: posterName, guides: true, sizes, files: {} };
  for (const path of files(root)) manifest.files[path] = digest(join(root, path));
  writeFileSync(join(root, "artifact.json"), JSON.stringify(manifest, null, 2) + "\n");
  verify(root);
  return root;
}
export function snapshotVersion(snapshot) {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuid.test(snapshot.deploymentId) || !uuid.test(snapshot.versionId)) throw new Error("Invalid Worker rollback snapshot");
  return snapshot.versionId;
}
export function deploymentSnapshot(deployments) {
  if (!Array.isArray(deployments) || !deployments.length) throw new Error("No Worker deployments returned");
  const latest = [...deployments].sort((a, b) => b.created_on.localeCompare(a.created_on))[0];
  const active = latest.versions?.filter(version => version.percentage > 0);
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuid.test(latest.id) || active?.length !== 1 || active[0].percentage !== 100 || !uuid.test(active[0].version_id)) throw new Error("Worker deployment is not one stable version");
  return { deploymentId: latest.id, versionId: active[0].version_id, created: latest.created_on };
}
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, ...args] = process.argv.slice(2);
  if (command === "stage") console.log(stage(...args));
  else if (command === "verify") console.log(JSON.stringify(verify(args[0])));
  else if (command === "snapshot-version") console.log(snapshotVersion(JSON.parse(readFileSync(args[0]))));
  else if (command === "snapshot") console.log(JSON.stringify(deploymentSnapshot(JSON.parse(readFileSync(args[0]))), null, 2));
  else throw new Error("Use stage, verify, or snapshot");
}
