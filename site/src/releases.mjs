// Pure helpers for the release downloads on nextshot.dev: which file names
// the Worker may serve from R2, and what latest.json must hold. No Cloudflare
// APIs here, so Node can test them (site/test/releases.test.mjs).

// R2 key of the record that says which version /download serves.
export const LATEST_KEY = "latest.json";

// A published file: Nextshot-<MAJOR>.<MINOR>.<PATCH>.<dmg|zip|dmg.sha256|json>.
// The date builds that shipped before versions also match, with their commit:
// Nextshot-2026.10.24-9d3afc7.dmg. The name holds no slash, so a request can
// only reach files directly under releases/.
const FILE = /^Nextshot-[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9a-f]{7})?\.(?:dmg|zip|dmg\.sha256|json)$/;

const SEMVER = /^[0-9]+\.[0-9]+\.[0-9]+$/;
const SHA256 = /^[0-9a-f]{64}$/;

/** The R2 key for a published file name, or null when the name is not allowed. */
export function releaseKey(name) {
  return typeof name === "string" && FILE.test(name) ? `releases/${name}` : null;
}

/** The Content-Type for a published file name. */
export function contentType(name) {
  if (name.endsWith(".dmg")) return "application/x-apple-diskimage";
  if (name.endsWith(".zip")) return "application/zip";
  if (name.endsWith(".json")) return "application/json";
  return "text/plain; charset=utf-8";
}

/**
 * True when a Range header asks for bytes that do not exist: a single range
 * that starts at or past the end of the file, or the last zero bytes. R2 does
 * not refuse these. It ignores the header and sends the whole file, so the
 * Worker answers 416 itself. Any other header (no header, several ranges, odd
 * text) is left to R2, which ignores what it cannot read.
 */
export function unsatisfiableRange(header, size) {
  const match = /^bytes=([0-9]*)-([0-9]*)$/.exec(header ?? "");
  if (!match) return false;
  const [, first, last] = match;
  if (first === "" && last === "") return false;
  if (first === "") return Number(last) === 0;
  return Number(first) >= size;
}

/**
 * Reads latest.json. Returns the record, or null when the text is not JSON or
 * a field is missing or has the wrong shape. The release script writes the
 * record (scripts/release-lib.sh), and /download redirects to its `file`, so
 * the Worker checks every field it uses.
 */
export function parseLatest(text) {
  let record;
  try {
    record = JSON.parse(text);
  } catch {
    return null;
  }
  if (!record || typeof record !== "object") return null;
  const { version, build, file, size, sha256 } = record;
  if (typeof version !== "string" || !SEMVER.test(version)) return null;
  if (!Number.isInteger(build) || build < 1) return null;
  if (releaseKey(file) === null || !file.endsWith(".dmg")) return null;
  if (!Number.isInteger(size) || size < 1) return null;
  if (typeof sha256 !== "string" || !SHA256.test(sha256)) return null;
  return {
    version,
    build,
    file,
    size,
    sha256,
    commit: typeof record.commit === "string" ? record.commit : null,
    released: typeof record.released === "string" ? record.released : null,
    notes: typeof record.notes === "string" ? record.notes : "",
  };
}
