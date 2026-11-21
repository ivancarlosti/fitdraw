# MCP-enabled, self-hosted Fitdraw image

- **Status:** approved, in implementation
- **Date:** 2026-11-20
- **Scope:** one all-in-one container image

## Context

Fitdraw ships the prebuilt Excalidraw frontend (`excalidraw/excalidraw:latest`) behind nginx with
branding/promo elements hidden by CSS/JS patches. Everything else still points at Excalidraw's
public infrastructure: collaboration rooms (`oss-collab.excalidraw.com`), scene sharing
(`json.excalidraw.com`), the AI/plus/docs links, and the library browser.

`excalidraw/excalidraw-mcp` (v0.3.2) is the official MCP App server. It exposes the tools
`read_me`, `create_view`, `export_to_excalidraw`, `save_checkpoint`, `read_checkpoint` over
stateless streamable HTTP on `POST /mcp`. Its UI is shipped inside the release asset
`excalidraw-mcp-app.mcpb` and is served through MCP `resources/read`, not as an HTTP asset.
Two of its behaviours are hard-coded to Excalidraw's cloud:

- `export_to_excalidraw` POSTs the encrypted scene to `https://json.excalidraw.com/api/v2/post/`
  and returns `https://excalidraw.com/#json=<id>,<key>`;
- the MCP App UI loads Excalidraw 0.18 + React 19 + morphdom from `https://esm.sh` at runtime.

Goal: Fitdraw must be able to open the links the MCP server produces, keep every other
`*.excalidraw.com` dependency local, and hand out MCP access from the same container — without
breaking the Excalidraw Library.

## Goal

1. Single image, single public port: nginx + collaboration room + MCP server + local scene store.
2. Only `libraries.excalidraw.com` is allowed to remain as a remote Excalidraw-owned host
   (plus `raw.githubusercontent.com/excalidraw/…` for library PR installs and the bare
   `"excalidraw.com"` hostname validator used by `#addLibrary=`).
3. The MCP UI must load with **no** request to `esm.sh`, only from the Fitdraw origin.
4. Version pins are tracked in the repo and enforced by CI; the host scrub is a build-time gate,
   so an upstream refactor fails the build instead of silently leaking traffic.

## Non-goals (documented residuals)

- **Firebase** (Excalidraw's GCP project) stays: it backs live-room scene persistence and
  image/file uploads for share links. Removing it requires rebuilding the frontend from patched
  source, because images are uploaded separately from the encrypted scene blob and Firestore's
  protocol cannot be emulated locally.
- Live-room injection from MCP: room payloads are encrypted end-to-end with the key only in the
  URL fragment, so a relay cannot push into a running canvas.
- Horizontal scaling of rooms (in-memory socket.io state).

## Architecture

```
container fitdraw :80 (single public port)
  PID 1  selfhost/supervisor.mjs
          ├─ nginx             :80    static + proxy locations
          ├─ excalidraw-room   :3002  node 22, /socket.io/
          ├─ MCP server        :3001  POST /mcp (stateless)
          └─ scene store       :3003  POST|GET /api/v2/*
  nginx also serves /mcp-ui/vendor/*  (locally mirrored esm.sh module graph)
  volume /var/lib/fitdraw/scenes      (opaque encrypted blobs, TTL)
```

Routing: `/` static · `/socket.io/` room · `/mcp` MCP · `/api/v2/` scene store ·
`/mcp-ui/` mirrored MCP UI assets · `/healthz`.

## Steps

1. Org scaffolding: `.dockerignore`, `.gitignore`, `plans/`, `docs/`.
2. `selfhost/scene-store/server.mjs` — zero-dependency encrypted blob store (`POST /api/v2/post/`
   → `{id}`, `GET /api/v2/<id>` → octet-stream, 10 MiB cap, TTL reaper, path guard).
3. `selfhost/scrub.mjs` — allow-list host rewrite of the baked frontend bundle + hard assertion.
4. `selfhost/mirror-mcp-ui.mjs` — crawl the MCP UI's esm.sh graph into `/mcp-ui/vendor` with
   relative imports; rewrite `mcp-app.html` to `__ORIGIN__/mcp-ui/vendor/*`.
5. `selfhost/patch-mcp.mjs` — runtime (startup) rewrite of the 3 hard-coded Excalidraw URLs,
   the CSP `resourceDomains`/`connectDomains`, and the `__ORIGIN__` placeholder.
6. `selfhost/nginx/default.conf`, `selfhost/supervisor.mjs`, `entrypoint.sh`, `healthcheck.sh`.
7. `Dockerfile`: room stage by digest, MCP download + sha256 verify, mirror build, scrub,
   `ARG`/`LABEL` metadata, non-root service users, `HEALTHCHECK`.
8. `docker/docker-compose.yml` → one service; `docker/.env.example`.
9. CI: `excalidraw_update.yml` tracks three pins in one commit; `build.yml` feeds build-args and
   asserts pin/file consistency.
10. Docs: `docs/mcp.md`, `docs/self-hosting.md`, README rewrite.
11. Build, run the validation suite, then the mandated post-push GitHub security review.

## Pins

| Pin | Value | Tracked in |
|---|---|---|
| Excalidraw frontend | `excalidraw/excalidraw:latest` | `.excalidraw-version` |
| Room image | `sha256:2fe999f9be4379e3ee282fc45d75d84a691a6383dde33544514cc395287c7a70` | `.excalidraw-room-digest` |
| MCP app | `v0.3.2`, asset sha256 `2b494012b5fee5937f9f7b86f04a76cc4a91ec843ee3339b93e4e15e415274ff` | `.excalidraw-mcp-version` |

## Risks

| Risk | Mitigation |
|---|---|
| Firebase still receives room scenes and uploaded images | Documented; Phase 2/3 item (patched-source build) |
| MCP iframe renders upstream Excalidraw 0.18 chrome/links | Documented; UI is upstream-owned |
| esm.sh mirror is fetched at build time (CDN content not hash-pinned upstream) | Manifest with per-file hashes printed + optional `mcp-ui.lock.json` verification; `MCP_UI_MODE=cdn` escape hatch |
| Room image is a 2023 amd64 JS artifact run on node 22 | Smoke test in CI; fallback is a source build at `03ff435…` |
| Upstream bundle changes break the host scrub | Build fails loudly (intended) |
| `/mcp` is unauthenticated with CORS `*` upstream | Optional `MCP_BEARER_TOKEN`, `limit_req`, `client_max_body_size`, documented `allow` list |
| No room HA | Single-container design by choice |
