# Self-hosting Fitdraw

Fitdraw is a single container: a patched Excalidraw bundle, a collaboration room, the MCP server and
an encrypted scene store, all served on port `80`.

```
                        ┌──────────────────────────── container ────────────────────────────┐
  browser ──:80────────►│ nginx  /            static bundle (patched, no excalidraw.com)     │
                        │        /socket.io/  ─► excalidraw-room       127.0.0.1:3002        │
  MCP client ──:80─────►│        /mcp         ─► excalidraw-mcp        127.0.0.1:3001        │
                        │        /api/v2/     ─► scene store           127.0.0.1:3003        │
                        │        /mcp-ui/     →  mirrored MCP App UI modules                 │
                        │        /healthz     →  supervisor liveness                         │
                        │                                                                    │
                        │ PID 1 selfhost/supervisor.mjs                                      │
                        │ volume /var/lib/fitdraw/scenes  (encrypted blobs, TTL)             │
                        └────────────────────────────────────────────────────────────────────┘
```

`nginx` runs as root (it must bind `:80` and drop workers to `nginx`); the three node services run as
`fitdraw` (uid/gid `10001`). The supervisor restarts any service that exits, with exponential
backoff, and forwards `SIGTERM` for a clean stop.

## Quick start

```bash
git clone https://github.com/ivancarlosti/fitdraw.git
cd fitdraw/docker
cp .env.example .env          # set FITDRAW_PUBLIC_URL
docker compose up -d
```

Open <http://localhost:3030>. Share a drawing link, or configure an MCP client against
`http://localhost:3030/mcp` (see [mcp.md](mcp.md)).

Without compose:

```bash
docker run -d --name fitdraw \
  -p 3030:80 \
  -e FITDRAW_PUBLIC_URL=http://localhost:3030 \
  -v fitdraw-scenes:/var/lib/fitdraw/scenes \
  ghcr.io/ivancarlosti/fitdraw:latest
```

`FITDRAW_PUBLIC_URL` is **required**: it is baked into MCP export links and into the MCP App UI's
import map at start-up. A wrong value produces links and frames that only work by accident.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `FITDRAW_PUBLIC_URL` | — (required) | Public origin, e.g. `https://fitdraw.example.com`. No path, no trailing slash. |
| `FITDRAW_PORT` | `3030` | Compose only: host port published for container port 80. |
| `SCENE_TTL_DAYS` | `30` | Days an encrypted scene stays on disk. `0` disables expiry. |
| `SCENE_DATA_DIR` | `/var/lib/fitdraw/scenes` | Where blobs are stored; mount a volume here. |
| `SCENE_MAX_BYTES` | `10485760` | Largest accepted scene (10 MiB). |
| `MCP_BEARER_TOKEN` | *(empty)* | When set, `POST /mcp` requires `Authorization: Bearer <token>`. |
| `ENABLE_MCP` | `1` | `0` disables the MCP server (and its health probe). |
| `ENABLE_ROOM` | `1` | `0` disables live collaboration. |
| `ENABLE_STORE` | `1` | `0` disables the scene store — share links stop working. |
| `MCP_UI_MODE` | `mirror` (build arg) | `cdn` keeps the MCP UI on esm.sh instead of the local mirror. |
| `ROOM_CORS_ORIGIN` | `*` | Passed to the room's socket.io CORS setting. |

## TLS / reverse proxy

The container speaks plain HTTP on `80`; terminate TLS in front of it. Two rules matter:

1. forward `Upgrade`/`Connection` for `/socket.io/` (websocket collaboration);
2. do not rewrite or strip `/mcp-ui/**` response headers — the MCP iframe needs
   `Access-Control-Allow-Origin: *` and `Cross-Origin-Resource-Policy: cross-origin`.

**Caddy** (simplest):

```
fitdraw.example.com {
    reverse_proxy 127.0.0.1:3030
}
```

**nginx**:

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
    listen 443 ssl http2;
    server_name fitdraw.example.com;
    # ssl_certificate ...;

    client_max_body_size 16m;

    location / {
        proxy_pass http://127.0.0.1:3030;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 86400s;
    }
}
```

Then set `FITDRAW_PUBLIC_URL=https://fitdraw.example.com` — the browser-facing origin, not the
container address.

### Optional: protect `/mcp` at the proxy

```nginx
location = /mcp {
    limit_req zone=mcp burst=20 nodelay;   # define the zone in the http block
    proxy_pass http://127.0.0.1:3030;
    # ...
}
```

Or set `MCP_BEARER_TOKEN` and let the container enforce it.

## Data, backup and retention

Everything stateful lives in one directory:

| Path | Content | Backup? |
|---|---|---|
| `/var/lib/fitdraw/scenes` | Encrypted scene blobs (`<id>.bin`, 0600) | Yes, if share links matter |
| `/tmp/mcp` | Patched MCP App, recreated at every start | No |
| `/tmp/excalidraw-mcp-checkpoints` | MCP checkpoints (`os.tmpdir()`), lost on restart | No |

```bash
# backup
docker run --rm -v desenho_desenho-scenes:/data -v "$PWD":/backup alpine \
  tar -czf /backup/scenes-$(date +%F).tar.gz -C /data .

# restore
docker run --rm -v desenho_desenho-scenes:/data -v "$PWD":/backup alpine \
  sh -c 'rm -rf /data/* && tar -xzf /backup/scenes-YYYY-MM-DD.tar.gz -C /data'
```

TTL: a sweep runs at start-up and hourly, deleting blobs whose mtime is older than
`SCENE_TTL_DAYS`. Restoring old blobs gives them a fresh mtime, so they get a full TTL window again.
Because decryption keys never reach the server, a lost blob is unrecoverable — that is the point.

Live collaboration is intentionally stateless: room membership lives in memory, so a restart ends
active sessions, and there is no horizontal scaling (one replica, `deploy.replicas: 1`).

## Hardening

```bash
docker run -d --name fitdraw \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /var/cache/nginx \
  --tmpfs /run \
  -v fitdraw-scenes:/var/lib/fitdraw/scenes \
  --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID \
  --cap-add NET_BIND_SERVICE --cap-add DAC_OVERRIDE \
  --security-opt no-new-privileges \
  -p 3030:80 -e FITDRAW_PUBLIC_URL=https://fitdraw.example.com \
  ghcr.io/ivancarlosti/fitdraw:latest
```

Notes on that command:

* `--read-only` works because the entrypoint patches a **copy** of the MCP app under `/tmp` and the
  scene volume stays writable; without the volume the store fails with `EROFS`.
* `CHOWN` is needed for the first-start ownership fix on a fresh named volume, `SETUID`/`SETGID` for
  dropping the node services to uid `10001`, `NET_BIND_SERVICE` for binding port 80.
* `no-new-privileges` is compatible: the supervisor never escalates, it only drops privileges.

What the container never does: run a shell as a request handler, listen on anything but `80`,
write outside `/tmp` and the scene volume, or fetch a module at runtime.

## What still talks to the internet

The bundle is scrubbed at build time: every `*.excalidraw.com` host is replaced, and the build fails
if one survives. What remains, deliberately or unavoidably:

| Host | Why |
|---|---|
| `libraries.excalidraw.com` | The Library browser. Kept on purpose — install/browse works as upstream. |
| `raw.githubusercontent.com/excalidraw/excalidraw-libraries` | "Add library" from a PR/build URL. |
| `link.excalidraw.com` | A hostname in the embed allow-list; never fetched. |
| `<project>.firebaseio.com`, `firebasestorage.googleapis.com`, `firestore.googleapis.com` | Excalidraw's own GCP project: live-room scene persistence and **image/file uploads** for share links. |
| `excalidraw.nyc3.cdn.digitaloceanspaces.com` | `<link rel=preload>` for three fonts in `index.html`; the fonts are also bundled locally, so this is a performance hint only. |
| `fonts.googleapis.com`, `fonts.gstatic.com` | `preconnect` hints from upstream `index.html`. |

Removing the Firebase dependency needs a frontend rebuilt from patched Excalidraw sources, because
images are uploaded to storage separately from the encrypted scene blob and Firestore's protocol
cannot be emulated locally. Until then, treat that traffic as a known residual: no drawing content
you keep in the local scene store leaves the network, but uploaded images in a live room do.

`/mcp-ui/vendor` is served locally, so the MCP App UI makes **zero** third-party requests.

## Logging and health

* All four processes log to the container's stdout/stderr with a `[service]` prefix.
* `HEALTHCHECK` runs `node /opt/selfhost/healthcheck.mjs` every 30 s: it checks `GET /healthz`,
  `GET /mcp-ui/manifest.json` and a TCP connect to each enabled service.
* nginx access logs are off by default (they would record scene ids and asset noise). Enable them by
  removing `access_log off;` from `/etc/nginx/conf.d/default.conf` — the container has no volume for
  logs, so use Docker's log driver.

## Upgrading and migrating

**From the old two-container setup** (`docker-compose.yml` with `excalidraw` + `excalidraw-room`):

1. The room is now internal — drop any proxy rule pointing at port `8082`, and remove any
   `VITE_APP_WS_SERVER_URL` sed/entrypoint override; the bundle is patched at build time.
2. `VITE_APP_WS_SERVER_URL` and `VITE_APP_PLUS_APP_URL` are gone. Replace them with
   `FITDRAW_PUBLIC_URL`.
3. Existing share links that point at `json.excalidraw.com` still resolve there; new links point at
   your instance. Nothing migrates between the two stores.

**Upgrading an image**: pull the new tag, then `docker compose up -d`. The scene volume and its
contents survive; `/tmp` state (MCP checkpoints) does not. Upstream pins (frontend tag, room digest,
MCP version) are bumped automatically by `.github/workflows/excalidraw_update.yml` and enforced by
`build.yml`, so `:latest` always reflects a tested combination.

