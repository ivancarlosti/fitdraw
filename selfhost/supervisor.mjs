#!/usr/bin/env node
/**
 * Fitdraw supervisor (PID 1).
 *
 * Runs four processes in one container and forwards signals/logs:
 *
 *   nginx      :80    static frontend + reverse proxy (master stays root)
 *   mcp        :3001  excalidraw-mcp, stateless POST /mcp
 *   room       :3002  excalidraw-room, socket.io
 *   store      :3003  encrypted scene store
 *
 * Each service is restarted with exponential backoff if it exits, and the
 * container shuts down cleanly on SIGTERM/SIGINT (Docker stop) or SIGQUIT.
 * `ENABLE_MCP` / `ENABLE_ROOM` / `ENABLE_STORE` can turn services off.
 */
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";

const UID = Number(process.env.FITDRAW_UID || 10001);
const GID = Number(process.env.FITDRAW_GID || 10001);
const SCENE_DATA_DIR = process.env.SCENE_DATA_DIR || "/var/lib/fitdraw/scenes";
const BACKOFF_MAX_MS = 30_000;
const SHUTDOWN_GRACE_MS = 15_000;

const log = (...args) => console.log(new Date().toISOString(), "[supervisor]", ...args);

function enabled(name, defaultValue = true) {
  const value = process.env[name];
  if (value === undefined || value === "") return defaultValue;
  return !["0", "false", "no", "off"].includes(String(value).toLowerCase());
}

const nodeBin = process.execPath;

const services = [
  {
    name: "store",
    command: nodeBin,
    args: ["/opt/selfhost/scene-store/server.mjs"],
    env: { PORT: process.env.SCENE_PORT || "3003", HOST: "127.0.0.1", SCENE_DATA_DIR },
    enabled: enabled("ENABLE_STORE"),
    runAsServiceUser: true,
  },
  {
    name: "room",
    command: nodeBin,
    args: ["/opt/room/dist/index.js"],
    cwd: "/opt/room",
    env: {
      PORT: process.env.ROOM_PORT || "3002",
      NODE_ENV: "production",
      CORS_ORIGIN: process.env.ROOM_CORS_ORIGIN || "*",
    },
    enabled: enabled("ENABLE_ROOM"),
    runAsServiceUser: true,
  },
  {
    name: "mcp",
    command: nodeBin,
    args: ["/tmp/mcp/dist/index.js"],
    cwd: "/tmp/mcp",
    env: { PORT: process.env.MCP_PORT || "3001" },
    enabled: enabled("ENABLE_MCP"),
    runAsServiceUser: true,
  },
  {
    name: "nginx",
    command: "/usr/sbin/nginx",
    args: ["-g", "daemon off;"],
    enabled: true,
    runAsServiceUser: false, // needs to bind :80 and setuid workers
  },
];

const children = new Map();
let stopping = false;

function pipeWithPrefix(stream, name, sink) {
  let buffer = "";
  stream.setEncoding("utf8");
  stream.on("data", (chunk) => {
    buffer += chunk;
    let index;
    while ((index = buffer.indexOf("\n")) >= 0) {
      sink(`${new Date().toISOString()} [${name}] ${buffer.slice(0, index)}`);
      buffer = buffer.slice(index + 1);
    }
    if (buffer.length > 8192) {
      sink(`${new Date().toISOString()} [${name}] ${buffer}`);
      buffer = "";
    }
  });
  stream.on("end", () => {
    if (buffer.trim()) sink(`${new Date().toISOString()} [${name}] ${buffer}`);
    buffer = "";
  });
}

function start(service) {
  if (stopping) return;
  const options = {
    cwd: service.cwd || "/",
    env: { ...process.env, ...service.env },
    stdio: ["ignore", "pipe", "pipe"],
  };
  if (service.runAsServiceUser && process.getuid && process.getuid() === 0) {
    options.uid = UID;
    options.gid = GID;
  }

  const child = spawn(service.command, service.args, options);
  service.restarts = service.restarts || 0;
  children.set(service.name, child);
  log(`started ${service.name} (pid ${child.pid})`);

  pipeWithPrefix(child.stdout, service.name, console.log);
  pipeWithPrefix(child.stderr, service.name, console.error);

  child.on("error", (err) => {
    console.error(`${new Date().toISOString()} [${service.name}] spawn failed: ${err.message}`);
  });

  child.on("exit", (code, signal) => {
    children.delete(service.name);
    if (stopping) return;
    service.restarts += 1;
    const delay = Math.min(BACKOFF_MAX_MS, 1000 * 2 ** (service.restarts - 1));
    log(`${service.name} exited (code=${code} signal=${signal}); restarting in ${delay}ms`);
    setTimeout(() => start(service), delay).unref();
  });
}

function shutdown(signal) {
  if (stopping) return;
  stopping = true;
  log(`received ${signal}, stopping ${children.size} service(s)`);
  for (const [name, child] of children) {
    log(`sending SIGTERM to ${name}`);
    try {
      child.kill("SIGTERM");
    } catch {
      /* already gone */
    }
  }
  const deadline = Date.now() + SHUTDOWN_GRACE_MS;
  const wait = setInterval(() => {
    if (children.size === 0 || Date.now() > deadline) {
      clearInterval(wait);
      for (const [name, child] of children) {
        log(`SIGKILL ${name}`);
        try {
          child.kill("SIGKILL");
        } catch {
          /* already gone */
        }
      }
      process.exit(0);
    }
  }, 200);
  wait.unref();
}

for (const signal of ["SIGTERM", "SIGINT", "SIGQUIT"]) {
  process.on(signal, () => shutdown(signal));
}

process.on("uncaughtException", (err) => {
  console.error(`${new Date().toISOString()} [supervisor] uncaught exception`, err);
  shutdown("uncaughtException");
});

// Cheap start-up sanity checks: fail fast with an actionable message.
function warnOnMissing(file, hint) {
  try {
    readFileSync(file);
  } catch {
    log(`WARN: ${file} is missing — ${hint}`);
  }
}
warnOnMissing("/tmp/mcp/dist/index.js", "the MCP App was not patched (see entrypoint.sh)");

for (const service of services) {
  if (service.enabled) start(service);
  else log(`${service.name} disabled by environment`);
}

if (children.size === 0) {
  log("ERROR: no service enabled, nothing to run");
  process.exit(1);
}
