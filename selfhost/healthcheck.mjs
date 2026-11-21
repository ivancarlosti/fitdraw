#!/usr/bin/env node
/**
 * Container health probe.
 *
 * Checks the same things a user needs: the static app answers on :80, the
 * mirrored MCP UI is served, and every enabled local service accepts a TCP
 * connection. Exits 0 (healthy) or 1 (unhealthy) with a one-line reason.
 */
import { connect } from "node:net";
import { request } from "node:http";

const TIMEOUT_MS = 4000;

function enabled(name) {
  const value = process.env[name];
  if (value === undefined || value === "") return true;
  return !["0", "false", "no", "off"].includes(String(value).toLowerCase());
}

function tcp(port) {
  return new Promise((resolve) => {
    const socket = connect({ host: "127.0.0.1", port });
    const done = (ok, reason) => {
      socket.destroy();
      resolve({ ok, reason });
    };
    socket.setTimeout(TIMEOUT_MS, () => done(false, `port ${port} timed out`));
    socket.once("connect", () => done(true, `port ${port}`));
    socket.once("error", (err) => done(false, `port ${port}: ${err.code || err.message}`));
  });
}

function http(path, expect = 200) {
  return new Promise((resolve) => {
    const req = request(
      { host: "127.0.0.1", port: 80, path, method: "GET", timeout: TIMEOUT_MS },
      (res) => {
        res.resume();
        resolve({
          ok: res.statusCode === expect,
          reason: `GET ${path} -> ${res.statusCode}`,
        });
      },
    );
    req.on("timeout", () => {
      req.destroy();
      resolve({ ok: false, reason: `GET ${path} timed out` });
    });
    req.on("error", (err) => resolve({ ok: false, reason: `GET ${path}: ${err.code || err.message}` }));
    req.end();
  });
}

const checks = [http("/healthz"), http("/mcp-ui/manifest.json")];
if (enabled("ENABLE_MCP")) checks.push(tcp(Number(process.env.MCP_PORT || 3001)));
if (enabled("ENABLE_ROOM")) checks.push(tcp(Number(process.env.ROOM_PORT || 3002)));
if (enabled("ENABLE_STORE")) checks.push(tcp(Number(process.env.SCENE_PORT || 3003)));

const results = await Promise.all(checks);
const failed = results.filter((result) => !result.ok);
if (failed.length > 0) {
  console.error(`[healthcheck] unhealthy: ${failed.map((f) => f.reason).join("; ")}`);
  process.exit(1);
}
console.log(`[healthcheck] ok: ${results.map((r) => r.reason).join("; ")}`);
