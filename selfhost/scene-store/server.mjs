#!/usr/bin/env node
/**
 * Fitdraw scene store — zero-dependency, zero-knowledge encrypted blob store.
 *
 * Excalidraw's "shareable link" feature POSTs an end-to-end encrypted scene to
 * https://json.excalidraw.com/api/v2/post/ and later GETs
 * https://json.excalidraw.com/api/v2/<id>. The decryption key never leaves the
 * URL fragment, so this store only ever sees opaque ciphertext.
 *
 * Routes
 *   POST /api/v2/post/   raw body -> {"id":"<12 chars>"}
 *   GET  /api/v2/<id>    raw body (application/octet-stream)
 *   GET  /healthz        200 "ok"
 *
 * Environment
 *   PORT            listen port                        (default 3003)
 *   HOST            listen address                     (default 127.0.0.1)
 *   SCENE_DATA_DIR  storage directory (volume)         (default /var/lib/fitdraw/scenes)
 *   SCENE_TTL_DAYS  retention in days, 0 disables      (default 30)
 *   SCENE_MAX_BYTES maximum accepted scene size        (default 10485760 = 10 MiB)
 */
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

const PORT = Number(process.env.PORT || 3003);
const HOST = process.env.HOST || "127.0.0.1";
const DATA_DIR = process.env.SCENE_DATA_DIR || "/var/lib/fitdraw/scenes";
const TTL_DAYS = Number(process.env.SCENE_TTL_DAYS ?? 30);
const MAX_BYTES = Number(process.env.SCENE_MAX_BYTES || 10 * 1024 * 1024);
const ID_RE = /^[A-Za-z0-9_-]{12}$/; // matches Excalidraw's #json= parser
const SWEEP_INTERVAL_MS = 60 * 60 * 1000;

function log(...args) {
  console.log(new Date().toISOString(), "[scene-store]", ...args);
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  res.end(body);
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BYTES) {
      const err = new Error("payload too large");
      err.code = "TOO_LARGE";
      throw err;
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function handlePost(req, res) {
  let body;
  try {
    body = await readBody(req);
  } catch (err) {
    if (err.code === "TOO_LARGE") {
      // Excalidraw understands error_class in the JSON response body.
      return sendJson(res, 413, { error_class: "RequestTooLargeError" });
    }
    throw err;
  }
  if (body.length === 0) {
    return sendJson(res, 400, { error_class: "Error" });
  }

  const id = randomBytes(9).toString("base64url"); // 12 url-safe chars
  const target = path.join(DATA_DIR, `${id}.bin`);
  const tmp = path.join(DATA_DIR, `.${id}.${process.pid}.tmp`);
  await fs.writeFile(tmp, body, { mode: 0o600 });
  await fs.rename(tmp, target);
  log("stored", id, `${body.length} bytes`);
  return sendJson(res, 200, { id });
}

async function handleGet(res, id) {
  let stat;
  try {
    stat = await fs.stat(path.join(DATA_DIR, `${id}.bin`));
  } catch {
    return sendJson(res, 404, { error_class: "NotFoundError" });
  }
  const body = await fs.readFile(path.join(DATA_DIR, `${id}.bin`));
  res.writeHead(200, {
    "content-type": "application/octet-stream",
    "content-length": body.length,
    "cache-control": "public, max-age=31536000, immutable",
    "x-content-type-options": "nosniff",
    "last-modified": stat.mtime.toUTCString(),
  });
  res.end(body);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    const { pathname } = url;

    if (req.method === "GET" && pathname === "/healthz") {
      res.writeHead(200, { "content-type": "text/plain" });
      return res.end("ok\n");
    }

    if (pathname === "/api/v2/post/" || pathname === "/api/v2/post") {
      if (req.method !== "POST") {
        res.setHeader("allow", "POST");
        return sendJson(res, 405, { error_class: "Error" });
      }
      return await handlePost(req, res);
    }

    if (pathname.startsWith("/api/v2/")) {
      if (req.method !== "GET" && req.method !== "HEAD") {
        res.setHeader("allow", "GET, HEAD");
        return sendJson(res, 405, { error_class: "Error" });
      }
      const id = pathname.slice("/api/v2/".length);
      if (!ID_RE.test(id)) {
        return sendJson(res, 404, { error_class: "NotFoundError" });
      }
      return await handleGet(res, id);
    }

    return sendJson(res, 404, { error_class: "NotFoundError" });
  } catch (err) {
    log("error", err && err.message);
    if (!res.headersSent) sendJson(res, 500, { error_class: "Error" });
    else res.end();
  }
});

/** Drop scenes older than SCENE_TTL_DAYS. */
async function sweep() {
  if (!TTL_DAYS || TTL_DAYS <= 0) return;
  const cutoff = Date.now() - TTL_DAYS * 24 * 60 * 60 * 1000;
  let removed = 0;
  let entries = [];
  try {
    entries = await fs.readdir(DATA_DIR);
  } catch {
    return;
  }
  for (const entry of entries) {
    if (!entry.endsWith(".bin")) continue;
    const file = path.join(DATA_DIR, entry);
    try {
      const stat = await fs.stat(file);
      if (stat.mtimeMs < cutoff) {
        await fs.unlink(file);
        removed += 1;
      }
    } catch {
      /* raced with another sweep */
    }
  }
  if (removed > 0) log(`ttl sweep removed ${removed} scene(s) older than ${TTL_DAYS}d`);
}

await fs.mkdir(DATA_DIR, { recursive: true });
server.listen(PORT, HOST, () => {
  log(`listening on ${HOST}:${PORT} (dir=${DATA_DIR}, ttl=${TTL_DAYS}d, max=${MAX_BYTES}B)`);
  sweep();
  setInterval(sweep, SWEEP_INTERVAL_MS).unref();
});

for (const signal of ["SIGTERM", "SIGINT", "SIGQUIT"]) {
  process.on(signal, () => {
    log(`received ${signal}, shutting down`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  });
}
