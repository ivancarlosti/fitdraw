# MCP server

Fitdraw ships [`excalidraw/excalidraw-mcp`](https://github.com/excalidraw/excalidraw-mcp) inside the
same container as the whiteboard, so a chat client can draw diagrams that open directly on your
own instance.

Everything below assumes `FITDRAW_PUBLIC_URL=https://fitdraw.example.com`. The endpoint is:

```
POST https://fitdraw.example.com/mcp
```

It speaks **streamable HTTP** and is **stateless** — every request is a complete JSON-RPC
exchange, no session id, no sticky routing. A `GET` on the same path is not needed.

## Tools

| Tool | What it does |
|---|---|
| `read_me` | Returns the Excalidraw element-format reference (colors, bindings, examples). |
| `create_view` | Renders a diagram from an elements JSON array, streamed into the UI. |
| `export_to_excalidraw` | Encrypts the scene, stores it locally and returns `https://<your-host>/#json=<id>,<key>`. |
| `save_checkpoint` / `read_checkpoint` | Named snapshots for iterative edits (stored in the container's `/tmp`). |

`export_to_excalidraw` returns a link on **your** domain — clicking it opens the Fitdraw whiteboard
with the scene already loaded. The encryption key lives in the URL fragment, so the server (and the
scene store) only ever sees ciphertext.

## Client configuration

### Claude Code

```bash
claude mcp add --transport http fitdraw https://fitdraw.example.com/mcp
# with a bearer token (see below)
claude mcp add --transport http fitdraw https://fitdraw.example.com/mcp \
  --header "Authorization: Bearer $MCP_BEARER_TOKEN"
```

### Claude Desktop

Claude Desktop only talks to local (stdio) servers, so bridge it with `mcp-remote`:

```json
{
  "mcpServers": {
    "fitdraw": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://fitdraw.example.com/mcp"],
      "env": { "MCP_REMOTE_HEADERS": "{\"Authorization\":\"Bearer YOUR_TOKEN\"}" }
    }
  }
}
```

Drop the `env` block when `MCP_BEARER_TOKEN` is not set.

### Any other MCP client

Point it at the URL above, and send `Authorization: Bearer <token>` if a token is configured. No SSE
endpoint, no session, no special path.

## Smoke test

```bash
# 1. handshake + tool listing
curl -sS https://fitdraw.example.com/mcp \
  -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'

curl -sS https://fitdraw.example.com/mcp \
  -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# 2. export a scene and check the stored blob
curl -sS https://fitdraw.example.com/mcp \
  -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"export_to_excalidraw","arguments":{"json":"{\"type\":\"excalidraw\",\"version\":2,\"elements\":[],\"appState\":{},\"files\":{}}"}}}'
# -> {"content":[{"type":"text","text":"https://fitdraw.example.com/#json=<id>,<key>"}]}

curl -sS -o /dev/null -w '%{http_code}\n' https://fitdraw.example.com/api/v2/<id>
```

Responses are SSE framed (`event: message` + `data: {...}`), which is why the smoke test sends the
`accept` header.

## Bearer token

`/mcp` is unauthenticated by default: anyone who can reach the host can call the tools. Set a token
to require one:

```bash
# docker/.env
MCP_BEARER_TOKEN=$(openssl rand -hex 32)
```

The token is compared in constant time, and the check is skipped when the variable is empty. The
whiteboard, the collaboration room and the scene store are unaffected — a token protects tool calls
only. If you expose Fitdraw publicly without one, rate-limit `/mcp` at your reverse proxy.

## The UI runs from your origin

The MCP App UI (`dist/mcp-app.html`) normally pulls React 19, Excalidraw 0.18 and morphdom from
`https://esm.sh`. At **image build time** `selfhost/mirror-mcp-ui.mjs` crawls that module graph and
stores it under `/opt/mcp-ui` (≈440 files, ~16 MB, relative imports, hashed file names). At
container start `selfhost/patch-mcp.mjs` rewrites the app HTML to absolute
`https://<your-host>/mcp-ui/vendor/<hash>.js` URLs.

Consequences:

* the iframe makes **no** request to esm.sh — check with the browser network panel, or run
  `grep -c 'esm\.sh' /opt/mcp/dist/mcp-app.html` inside the container (expect `0`);
* nginx serves `/mcp-ui/` with `Access-Control-Allow-Origin: *` and
  `Cross-Origin-Resource-Policy: cross-origin`, because MCP hosts render the app in a sandboxed
  iframe with an opaque origin;
* `/mcp-ui/manifest.json` lists every mirrored file with its upstream URL, and the container health
  check asserts that it is served;
* `FITDRAW_PUBLIC_URL` must be the origin users actually reach. A wrong value breaks the import map
  and the UI renders an empty frame.

`--build-arg MCP_UI_MODE=cdn` keeps the upstream esm.sh imports instead (escape hatch if a future
release changes the module graph in a way the crawler cannot follow).

## How the scene store fits in

`selfhost/scene-store/server.mjs` implements the two endpoints Excalidraw's share links need:

| Route | Behaviour |
|---|---|
| `POST /api/v2/post/` | Stores the raw encrypted body, returns `{"id":"<12 chars>"}` |
| `GET /api/v2/<id>` | Returns the blob as `application/octet-stream` |
| Body > 10 MiB | `413 {"error_class":"RequestTooLargeError"}` |

* ids are 12-character base64url (`crypto.randomBytes(9)`) and are validated against
  `^[A-Za-z0-9_-]{12}$`, so a crafted path cannot escape the data directory;
* blobs are written atomically (`tmp` + `rename`, mode `0600`) into `/var/lib/fitdraw/scenes`, the
  `desenho-scenes` volume;
* `SCENE_TTL_DAYS` (default `30`) reaps older blobs hourly; `0` keeps them forever.

The scene is compressed and encrypted with AES-GCM in the browser before upload, and the key only
lives in the URL fragment, so the store is zero-knowledge.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `401 Unauthorized` from `/mcp` | `MCP_BEARER_TOKEN` is set; send `Authorization: Bearer <token>`. |
| Export link points at `localhost` | `FITDRAW_PUBLIC_URL` unset, or not the public origin. |
| Blank MCP App frame | `/mcp-ui/vendor/*` unreachable: wrong `FITDRAW_PUBLIC_URL`, a proxy stripping headers, or `MCP_UI_MODE=cdn` without internet. |
| `413` on export | Scene exceeds 10 MiB (images are stored separately from the scene JSON). |
| Export link opens but the scene never loads | The container was recreated without the volume, or the TTL reaped the blob. |
| `EROFS` in the logs when exporting | The container runs `--read-only` and `/var/lib/fitdraw/scenes` is not a volume/tmpfs. |

