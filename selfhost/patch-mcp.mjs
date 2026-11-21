#!/usr/bin/env node
/**
 * Fitdraw MCP runtime patch.
 *
 * The MCP App server bundles three hard-coded references to Excalidraw's cloud
 * plus a CSP allow-list for esm.sh. This script rewrites them at container
 * start-up (onto a writable copy of /opt/mcp), so the image stays deployable on
 * any domain without a rebuild.
 *
 * Environment
 *   FITDRAW_PUBLIC_URL  required, e.g. https://fitdraw.example.com (no path)
 *   SCENE_STORE_URL     default http://127.0.0.1:3003
 *
 * Usage: node selfhost/patch-mcp.mjs [--app /tmp/mcp]
 */
import { promises as fs } from "node:fs";
import path from "node:path";

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}

const appDir = arg("app", "/tmp/mcp");
const rawPublic = (process.env.FITDRAW_PUBLIC_URL || "").trim().replace(/\/+$/, "");
const storeUrl = (process.env.SCENE_STORE_URL || "http://127.0.0.1:3003").trim().replace(/\/+$/, "");

function fail(message) {
  console.error(`[patch-mcp] ERROR: ${message}`);
  process.exit(1);
}

if (!rawPublic) {
  fail("FITDRAW_PUBLIC_URL is required (e.g. https://fitdraw.example.com)");
}
let publicUrl;
try {
  const parsed = new URL(rawPublic);
  if (!/^https?:$/.test(parsed.protocol)) throw new Error("protocol");
  if (parsed.pathname !== "/" || parsed.search || parsed.hash) {
    throw new Error("must be an origin without path/query/fragment");
  }
  publicUrl = parsed.origin;
} catch (err) {
  fail(`FITDRAW_PUBLIC_URL is not a valid origin: ${rawPublic} (${err.message})`);
}

/** [pattern, replacement, expectedOccurrences] applied to every server bundle. */
const SHARED_RULES = [
  ["https://json.excalidraw.com/api/v2/post/", `${storeUrl}/api/v2/post/`, 1],
  ["https://excalidraw.com/#json=", `${publicUrl}/#json=`, 1],
  [
    "Upload diagram to excalidraw.com and return shareable URL.",
    "Upload diagram to Fitdraw and return a shareable URL.",
    1,
  ],
  ['resourceDomains: ["https://esm.sh"]', `resourceDomains: ["${publicUrl}"]`, 1],
  ['connectDomains: ["https://esm.sh"]', `connectDomains: ["${publicUrl}"]`, 1],
];

/**
 * Optional bearer-token gate for /mcp, injected as express middleware right
 * after CORS. It is inert until MCP_BEARER_TOKEN is set at run time, so the
 * image can be published publicly without turning the MCP endpoint into an open
 * proxy for LLM tool calls.
 */
const AUTH_ANCHOR = "app.use(import_cors.default());";
const AUTH_MIDDLEWARE = [
  AUTH_ANCHOR,
  'app.use(async (req, res, next) => { const expected = process.env.MCP_BEARER_TOKEN; if (!expected) return next(); const enc = new TextEncoder(); const digest = async (value) => new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(value))); const [got, want] = await Promise.all([digest(req.headers.authorization || ""), digest("Bearer " + expected)]); let diff = 0; for (let i = 0; i < got.length; i++) diff |= got[i] ^ want[i]; if (diff === 0) return next(); res.status(401).set("content-type", "application/json").send(JSON.stringify({ jsonrpc: "2.0", error: { code: -32001, message: "Unauthorized" }, id: null })); });',
].join("\n");

const INDEX_ONLY_RULES = [[AUTH_ANCHOR, AUTH_MIDDLEWARE, 1]];


const SERVER_BUNDLES = ["dist/index.js", "dist/server.js"];
const UI_FILE = "dist/mcp-app.html";
const ORIGIN_PLACEHOLDER = "__FITDRAW_ORIGIN__";

function countOccurrences(haystack, needle) {
  return haystack.split(needle).length - 1;
}

let failures = 0;
let patched = 0;

for (const relative of SERVER_BUNDLES) {
  const file = path.join(appDir, relative);
  let source;
  try {
    source = await fs.readFile(file, "utf8");
  } catch {
    console.warn(`[patch-mcp] WARN: ${relative} not found, skipping`);
    continue;
  }
  const rules = relative === "dist/index.js" ? [...SHARED_RULES, ...INDEX_ONLY_RULES] : SHARED_RULES;
  for (const [from, to, expected] of rules) {
    const found = countOccurrences(source, from);
    if (found !== expected) {
      console.error(
        `[patch-mcp] ERROR: ${relative}: expected ${expected} occurrence(s) of "${from}", found ${found}`,
      );
      failures += 1;
      continue;
    }
    source = source.split(from).join(to);
    patched += 1;
  }
  await fs.writeFile(file, source);
}

// ---- MCP App UI: resolve the origin placeholder -------------------------
const uiPath = path.join(appDir, UI_FILE);
try {
  let ui = await fs.readFile(uiPath, "utf8");
  const placeholders = countOccurrences(ui, ORIGIN_PLACEHOLDER);
  if (placeholders > 0) {
    ui = ui.split(ORIGIN_PLACEHOLDER).join(publicUrl);
    await fs.writeFile(uiPath, ui);
    patched += 1;
    console.log(`[patch-mcp] ${UI_FILE}: resolved ${placeholders} origin reference(s)`);
  } else {
    console.log(`[patch-mcp] ${UI_FILE}: no origin placeholder (CDN mode?)`);
  }
  if (ui.includes("https://esm.sh")) {
    console.error("[patch-mcp] ERROR: MCP UI still references esm.sh");
    failures += 1;
  }
} catch {
  console.warn(`[patch-mcp] WARN: ${UI_FILE} not found, skipping`);
}

if (failures > 0) {
  fail(`${failures} replacement(s) did not match the expected layout`);
}

console.log(
  `[patch-mcp] ${patched} edit(s) applied — public=${publicUrl} store=${storeUrl}`,
);
