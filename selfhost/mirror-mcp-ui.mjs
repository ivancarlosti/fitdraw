#!/usr/bin/env node
/**
 * Fitdraw MCP UI mirror — makes the Excalidraw MCP App UI independent of
 * esm.sh.
 *
 * The MCP App HTML shipped in excalidraw-mcp-app.mcpb loads Excalidraw,
 * React 19 and morphdom from https://esm.sh through an import map. Without a
 * mirror, every chat client that renders the app hits that CDN. This script
 * crawls the module graph at image-build time and stores it under
 * /mcp-ui/vendor, then rewrites mcp-app.html to load from the Fitdraw origin.
 *
 * Import specifiers inside the vendor files are rewritten to *sibling-relative*
 * paths (./<hash>.js), so the vendor tree is origin independent and can be
 * served read-only. Only mcp-app.html carries the __FITDRAW_ORIGIN__ placeholder
 * that selfhost/patch-mcp.mjs substitutes at container start-up.
 *
 * Usage: node selfhost/mirror-mcp-ui.mjs --app <mcp-app.html> --out <dir> [--mode mirror|cdn]
 */
import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}

const appHtml = arg("app");
const outDir = arg("out");
const mode = arg("mode", "mirror");
const ORIGIN = "__FITDRAW_ORIGIN__";
const ALLOWED_HOSTS = new Set(["esm.sh"]);
const EXT_BY_TYPE = [
  [/javascript|ecmascript/i, ".js"],
  [/text\/css/i, ".css"],
  [/image\/svg/i, ".svg"],
  [/image\/png/i, ".png"],
  [/image\/jpeg/i, ".jpg"],
  [/font\/woff2/i, ".woff2"],
  [/font\/woff/i, ".woff"],
  [/application\/json/i, ".json"],
  [/text\/plain/i, ".txt"],
  [/application\/wasm/i, ".wasm"],
];

if (!appHtml || !outDir) {
  console.error("usage: mirror-mcp-ui.mjs --app <mcp-app.html> --out <dir> [--mode mirror|cdn]");
  process.exit(2);
}

function log(...args) {
  console.log("[mcp-ui]", ...args);
}

if (mode === "cdn") {
  log("mode=cdn — leaving the upstream esm.sh imports untouched");
  process.exit(0);
}

const vendorDir = path.join(outDir, "vendor");
await fs.rm(outDir, { recursive: true, force: true });
await fs.mkdir(vendorDir, { recursive: true });

/** url -> { file, ext } memo, so every specifier resolves to the same file. */
const memo = new Map();
const manifest = [];
const hostSeen = new Set();
let importMap = {};

function fingerprint(url) {
  return createHash("sha256").update(url).digest("hex").slice(0, 32);
}

function extFor(contentType, url) {
  for (const [re, ext] of EXT_BY_TYPE) if (re.test(contentType)) return ext;
  const urlExt = path.extname(new URL(url).pathname).toLowerCase();
  if (/^\.[a-z0-9]{2,5}$/.test(urlExt)) return urlExt;
  return ".js";
}

function assertHost(url) {
  const parsed = new URL(url);
  if (parsed.protocol === "data:" || parsed.protocol === "blob:") return;
  if (parsed.protocol !== "https:") throw new Error(`unexpected protocol in ${url}`);
  hostSeen.add(parsed.host);
  if (!ALLOWED_HOSTS.has(parsed.host)) {
    throw new Error(`refusing to mirror unknown host ${parsed.host} (${url})`);
  }
}

/**
 * Find every real module specifier in a (minified) ES module.
 *
 * Minified prose can contain text such as `import { createStore } from
 * 'zustand/vanilla'` inside a warning string, so a naive `from"..."` regex
 * produces false positives. Only path-shaped specifiers and bare specifiers
 * that exist in the import map count as real imports.
 */
function specifiers(source) {
  const found = new Set();
  const isModuleSpec = (spec) => /^(https?:\/\/|\/|\.{1,2}\/)/.test(spec) || Boolean(importMap[spec]);
  for (const match of source.matchAll(/[}*]\s*from\s*["']([^"']+)["']/g)) {
    if (isModuleSpec(match[1])) found.add(match[1]);
  }
  for (const match of source.matchAll(/\bfrom\s*["']([^"']+)["']/g)) {
    if (isModuleSpec(match[1])) found.add(match[1]);
  }
  for (const match of source.matchAll(/\bimport\s*["']([^"']+)["']/g)) {
    if (isModuleSpec(match[1])) found.add(match[1]);
  }
  for (const match of source.matchAll(/\bimport\s*\(\s*["']([^"']+)["']\s*\)/g)) {
    if (isModuleSpec(match[1])) found.add(match[1]);
  }
  return [...found];
}

/** Resolve a specifier against the module that contains it. */
function resolveSpecifier(spec, baseUrl) {
  if (spec.startsWith("data:") || spec.startsWith("blob:")) return null;
  if (/^\.\.?\//.test(spec) || spec.startsWith("/") || /^https?:\/\//.test(spec)) {
    return new URL(spec, baseUrl).href;
  }
  // Bare specifier: esm.sh normally emits absolute paths, but fall back to the
  // import map embedded in the HTML.
  const mapped = importMap[spec];
  if (!mapped) throw new Error(`bare specifier "${spec}" in ${baseUrl} is not in the import map`);
  return new URL(mapped).href;
}

async function fetchModule(url) {
  assertHost(url);
  const response = await fetch(url, {
    headers: { "user-agent": "fitdraw-mirror/1.0", accept: "*/*" },
    redirect: "follow",
  });
  if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);
  const finalUrl = response.url || url;
  assertHost(finalUrl);
  return { response, finalUrl };
}

async function mirror(url) {
  const hit = memo.get(url);
  if (hit) return hit;

  const { response, finalUrl } = await fetchModule(url);
  const contentType = response.headers.get("content-type") || "";
  const ext = extFor(contentType, finalUrl);
  const file = `${fingerprint(finalUrl)}${ext}`;
  const entry = { file, ext };
  memo.set(url, entry);
  memo.set(finalUrl, entry);

  if (ext === ".js") {
    const source = await response.text();
    const rewrite = new Map();
    for (const spec of specifiers(source)) {
      const resolved = resolveSpecifier(spec, finalUrl);
      if (!resolved) continue;
      const child = await mirror(resolved);
      rewrite.set(spec, `./${child.file}`);
    }
    let output = source;
    for (const [spec, replacement] of rewrite) output = output.split(spec).join(replacement);
    // esm.sh emits a "/* esm.sh - pkg@ver */" banner, so assert on specifiers
    // rather than on the raw string.
    const residual = specifiers(output).filter((spec) => /esm\.sh/.test(spec));
    if (residual.length > 0) {
      throw new Error(`unrewritten specifier(s) in ${finalUrl}: ${residual.join(", ")}`);
    }
    await fs.writeFile(path.join(vendorDir, file), output);
    manifest.push({ url: finalUrl, file, kind: "module", imports: rewrite.size });
  } else if (ext === ".css") {
    let source = await response.text();
    const rewrite = new Map();
    for (const match of source.matchAll(/url\(\s*(?:(["'])?)(https:\/\/esm\.sh\/[^"')]+)\1\s*\)/g)) {
      const child = await mirror(match[2]);
      rewrite.set(match[2], `./${child.file}`);
    }
    for (const [from, to] of rewrite) source = source.split(from).join(to);
    if (/url\(\s*["']?https:\/\/esm\.sh|@import\s+["']https:\/\/esm\.sh/.test(source)) {
      throw new Error(`esm.sh asset reference survived in CSS from ${finalUrl}`);
    }
    await fs.writeFile(path.join(vendorDir, file), source);
    manifest.push({ url: finalUrl, file, kind: "css", assets: rewrite.size });
  } else {
    const buffer = Buffer.from(await response.arrayBuffer());
    await fs.writeFile(path.join(vendorDir, file), buffer);
    manifest.push({ url: finalUrl, file, kind: "asset", bytes: buffer.length });
  }
  return entry;
}

// ---- seed from the MCP App HTML ----------------------------------------
let html = await fs.readFile(appHtml, "utf8");

const mapMatch = html.match(/<script type="importmap">([\s\S]*?)<\/script>/);
if (!mapMatch) throw new Error("no import map found in mcp-app.html");
importMap = JSON.parse(mapMatch[1]).imports || {};
log(`import map entries: ${Object.keys(importMap).join(", ")}`);

const seeds = new Set(Object.values(importMap));
for (const spec of specifiers(html)) {
  if (/^https?:\/\//.test(spec)) seeds.add(spec);
}
if (seeds.size === 0) throw new Error("no esm.sh entry points found in mcp-app.html");
log(`seeding crawl with ${seeds.size} entry point(s)`);

for (const url of seeds) await mirror(url);

// ---- rewrite the HTML --------------------------------------------------
for (const url of seeds) {
  const entry = memo.get(url);
  if (entry) html = html.split(url).join(`${ORIGIN}/mcp-ui/vendor/${entry.file}`);
}

// Any remaining esm.sh URL (inline CSS, preloads, plain strings).
const leftoverMatches = [...html.matchAll(/https:\/\/esm\.sh\/[^"')\s]+/g)].map((m) => m[0]);
const leftovers = [...new Set(leftoverMatches)];
for (const url of leftovers) {
  const entry = await mirror(url);
  html = html.split(url).join(`${ORIGIN}/mcp-ui/vendor/${entry.file}`);
}

if (html.includes("esm.sh")) throw new Error("esm.sh reference survived in mcp-app.html");
if (!html.includes(ORIGIN)) throw new Error("mcp-app.html does not reference the mirrored tree");

await fs.writeFile(appHtml, html);

// ---- manifest ----------------------------------------------------------
const digest = createHash("sha256").update(JSON.stringify(manifest)).digest("hex");
await fs.writeFile(
  path.join(outDir, "manifest.json"),
  JSON.stringify({ generatedAt: new Date().toISOString(), digest, files: manifest }, null, 2) + "\n",
);

const modules = manifest.filter((m) => m.kind === "module").length;
log(`mirrored ${manifest.length} file(s) (${modules} JS modules) from ${[...hostSeen].join(", ")}`);
log(`manifest digest: sha256:${digest}`);

