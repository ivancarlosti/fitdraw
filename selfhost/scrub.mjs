#!/usr/bin/env node
/**
 * Fitdraw host scrub — rewrites Excalidraw's cloud hostnames in the baked
 * frontend bundle so a self-hosted deployment never talks to *.excalidraw.com,
 * except for the Library (libraries.excalidraw.com) which the user explicitly
 * keeps working.
 *
 * Usage: node selfhost/scrub.mjs <html-root> [--keep-maps]
 *
 * The script is a build gate: it exits non-zero if a forbidden host survives or
 * if a host we must keep disappears. That way an upstream bundle refactor fails
 * the image build instead of silently leaking traffic to excalidraw.com.
 */
import { promises as fs } from "node:fs";
import path from "node:path";

const root = process.argv[2];
if (!root) {
  console.error("usage: scrub.mjs <html-root> [--keep-maps]");
  process.exit(2);
}
const keepMaps = process.argv.includes("--keep-maps");

// Ordered: specific paths first, then whole hosts. Replacement values are
// root-relative so the bundle keeps working on any deployment origin.
const RULES = [
  ["https://json.excalidraw.com/api/v2/post/", "/api/v2/post/"],
  ["https://json.excalidraw.com/api/v2/", "/api/v2/"],
  ["https://json.excalidraw.com", "/api/v2"],
  ["https://us-central1-excalidraw-room-persistence.cloudfunctions.net/libraries", "/api/library-disabled"],
  ["https://oss-collab.excalidraw.com", "/"],
  ["https://oss-ai.excalidraw.com", "/"],
  ["https://plus.excalidraw.com", "/"],
  ["https://app.excalidraw.com", "/"],
  ["https://link.excalidraw.com", "/"],
  ["https://staging.excalidraw.com", "/"],
  ["http://docs.excalidraw.com", "/"],
  ["https://docs.excalidraw.com", "/"],
  // Bare origin last. The path-prefixed form runs first so that
  // https://excalidraw.com/og-image-3.png becomes /og-image-3.png rather than
  // a protocol-relative //og-image-3.png.
  ["https://excalidraw.com/", "/"],
  ["https://excalidraw.com", "/"],
];

// Files that only advertise excalidraw.com and must not survive a self-host.
const DELETE = ["sitemap.xml", "robots.txt"];

const TEXT_EXT = new Set([".js", ".mjs", ".cjs", ".css", ".html", ".htm", ".json", ".webmanifest", ".xml", ".txt", ".map", ".svg"]);

// Hosts allowed to remain (the Library exception plus non-fetched validators).
const ALLOWED_TOKEN = new Set(["libraries.excalidraw.com", "link.excalidraw.com", "excalidraw.com"]);
const FORBIDDEN_SCHEMED = /https?:\/\/(?:[a-z0-9-]+\.)*excalidraw\.com/gi;
const ANY_TOKEN = /(?:[a-z0-9-]+\.)*excalidraw\.com/gi;

async function* walk(dir) {
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(full);
    else if (entry.isFile()) yield full;
  }
}

const report = new Map();
const touched = [];
let deletedMaps = 0;
let deletedSeo = 0;

for (const file of await awaitArray(walk(root))) {
  const rel = path.relative(root, file);
  const ext = path.extname(file).toLowerCase();

  if (DELETE.includes(rel)) {
    await fs.rm(file, { force: true });
    deletedSeo += 1;
    continue;
  }
  if (ext === ".map" && !keepMaps) {
    await fs.rm(file, { force: true });
    deletedMaps += 1;
    continue;
  }
  if (!TEXT_EXT.has(ext)) continue;

  let source = await fs.readFile(file, "utf8");
  let changed = false;
  for (const [from, to] of RULES) {
    const count = source.split(from).length - 1;
    if (count === 0) continue;
    source = source.split(from).join(to);
    report.set(from, (report.get(from) || 0) + count);
    changed = true;
  }
  if (changed) {
    await fs.writeFile(file, source);
    touched.push(rel);
  }
}

// ---- gate 1: no forbidden host may remain -------------------------------
const violations = [];
for (const file of await awaitArray(walk(root))) {
  const ext = path.extname(file).toLowerCase();
  if (!TEXT_EXT.has(ext)) continue;
  const rel = path.relative(root, file);
  const source = await fs.readFile(file, "utf8");

  for (const match of source.matchAll(FORBIDDEN_SCHEMED)) {
    if (!/^https?:\/\/libraries\.excalidraw\.com/i.test(match[0])) {
      violations.push(`${rel}: ${match[0]}`);
    }
  }
  for (const match of source.matchAll(ANY_TOKEN)) {
    if (!ALLOWED_TOKEN.has(match[0].toLowerCase())) violations.push(`${rel}: ${match[0]}`);
  }
}
if (violations.length > 0) {
  console.error("[scrub] ERROR: forbidden Excalidraw hosts survived:");
  for (const v of [...new Set(violations)].slice(0, 40)) console.error("  -", v);
  process.exit(1);
}

// ---- gate 2: the Library exception must still be wired up ---------------
const bundle = (await Promise.all(
  (await listJs(root)).map((f) => fs.readFile(f, "utf8")),
)).join("\n");

const required = [
  ["library browse URL", "https://libraries.excalidraw.com"],
  ["library host validator", '"excalidraw.com"'],
  ["library PR installs", "raw.githubusercontent.com/excalidraw/excalidraw-libraries"],
  ["scene store post URL", "/api/v2/post/"],
];
const missing = required.filter(([, needle]) => !bundle.includes(needle));
if (missing.length > 0) {
  console.error("[scrub] ERROR: expected Selfhost wiring is missing:");
  for (const [label, needle] of missing) console.error(`  - ${label} (${needle})`);
  process.exit(1);
}

// ---- report ------------------------------------------------------------
console.log("[scrub] rewrote:");
for (const [from, count] of report) console.log(`  ${String(count).padStart(5)}  ${from}`);
console.log(`[scrub] deleted ${deletedMaps} sourcemap(s), ${deletedSeo} SEO file(s)`);
console.log(`[scrub] touched ${touched.length} file(s); gates passed (library kept, no remote hosts)`);

async function listJs(dir) {
  const out = [];
  for (const file of await awaitArray(walk(dir))) {
    if (/\.(js|mjs)$/i.test(file)) out.push(file);
  }
  return out;
}

async function awaitArray(iterable) {
  const out = [];
  for await (const item of iterable) out.push(item);
  return out;
}
