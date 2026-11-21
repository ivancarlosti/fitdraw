# FitDraw

**A clean, white-label distribution of [Excalidraw](https://github.com/excalidraw/excalidraw)** — the open-source virtual whiteboard for sketching hand-drawn diagrams.

FitDraw removes branding, promotional links, sign-up nudges, analytics, and collaboration upsells from the UI. Social links are redirected to FitDraw's own profiles, and the page title is set to **Fitdraw Whiteboard**.

<!-- buttons -->
[![Stars](https://img.shields.io/github/stars/ivancarlosti/fitdraw?label=⭐%20Stars&color=gold&style=flat)](https://github.com/ivancarlosti/fitdraw/stargazers)
[![Watchers](https://img.shields.io/github/watchers/ivancarlosti/fitdraw?label=Watchers&style=flat&color=red)](https://github.com/sponsors/ivancarlosti)
[![Forks](https://img.shields.io/github/forks/ivancarlosti/fitdraw?label=Forks&style=flat&color=ff69b4)](https://github.com/sponsors/ivancarlosti)
[![Downloads](https://img.shields.io/github/downloads/ivancarlosti/fitdraw/total?label=Downloads&color=success)](https://github.com/ivancarlosti/fitdraw/releases)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/ivancarlosti/fitdraw?label=Activity)](https://github.com/ivancarlosti/fitdraw/pulse)
[![GitHub Issues](https://img.shields.io/github/issues/ivancarlosti/fitdraw?label=Issues&color=orange)](https://github.com/ivancarlosti/fitdraw/issues)  
[![License](https://img.shields.io/github/license/ivancarlosti/fitdraw?label=License)](LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/ivancarlosti/fitdraw?label=Last%20Commit)](https://github.com/ivancarlosti/fitdraw/commits)
[![Security](https://img.shields.io/badge/Security-View%20Here-purple)](https://github.com/ivancarlosti/fitdraw/security)
[![Code of Conduct](https://img.shields.io/badge/Code%20of%20Conduct-2.1-4baaaa)](https://github.com/ivancarlosti/fitdraw?tab=coc-ov-file)
<!-- endbuttons -->

## What's removed

- Excalidraw logo and home button
- Sign up / Sign in / Login buttons
- Excalidraw+ / Plus / Upgrade prompts
- Comments and Presentation tabs
- Discord invite
- Excalidraw+ promo card on the export dialog
- GitHub and Twitter/X links → redirected to FitDraw profiles
- AI features (Magic Frame, Text-to-Diagram)
- Share button and Shareable link card

## What's included

- **One container, one port.** nginx-served Excalidraw, the collaboration room, the MCP server and an
  encrypted scene store, supervised together (`selfhost/supervisor.mjs`).
- **Shareable links you own.** `https://your-host/#json=<id>,<key>` works exactly like upstream, but
  the ciphertext lands in a local volume, not on `json.excalidraw.com`. Keys never leave the URL
  fragment.
- **MCP support.** [`excalidraw-mcp`](https://github.com/excalidraw/excalidraw-mcp) v0.3.2 on
  `POST /mcp`: a chat client can draw a diagram and hand you a link that opens on *your* instance.
  See [docs/mcp.md](docs/mcp.md).
- **A fully local MCP App UI.** The React 19 + Excalidraw 0.18 module graph is mirrored at build time
  (`/mcp-ui/vendor`), so the app iframe never calls `esm.sh`.
- **The Library still works.** `libraries.excalidraw.com` is the only Excalidraw-owned host kept;
  browsing and installing libraries behaves as upstream.
- **A build-time host gate.** `selfhost/scrub.mjs` rewrites every other `*.excalidraw.com` URL and
  fails the build if one survives, so an upstream change can never silently leak traffic.

---

## Quick start

```bash
git clone https://github.com/ivancarlosti/fitdraw.git
cd fitdraw/docker
cp .env.example .env     # set FITDRAW_PUBLIC_URL to the origin users open
docker compose up -d
```

Open <http://localhost:3030>. Or without compose:

```bash
docker run -d --name fitdraw -p 3030:80 \
  -e FITDRAW_PUBLIC_URL=http://localhost:3030 \
  -v fitdraw-scenes:/var/lib/fitdraw/scenes \
  ghcr.io/ivancarlosti/fitdraw:latest
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `FITDRAW_PUBLIC_URL` | — (required) | Public origin, e.g. `https://fitdraw.example.com`. Used for MCP export links and the MCP UI import map. |
| `SCENE_TTL_DAYS` | `30` | Days an encrypted scene stays on disk (`0` = forever). |
| `MCP_BEARER_TOKEN` | *(empty)* | When set, `POST /mcp` requires `Authorization: Bearer <token>`. |
| `ENABLE_MCP` / `ENABLE_ROOM` / `ENABLE_STORE` | `1` | Turn an individual service off inside the container. |
| `FITDRAW_PORT` | `3030` | Compose only: host port to publish. |

Full list: [docs/self-hosting.md](docs/self-hosting.md#environment).

---

## MCP in one minute

```bash
claude mcp add --transport http fitdraw https://fitdraw.example.com/mcp
```

| Tool | Result |
|---|---|
| `read_me` | Excalidraw element-format reference |
| `create_view` | Renders a diagram from elements JSON |
| `export_to_excalidraw` | Stores the encrypted scene, returns `https://your-host/#json=<id>,<key>` |
| `save_checkpoint` / `read_checkpoint` | Named snapshots for iterative edits |

Client setup for Claude Code, Claude Desktop, Cursor and plain `curl`: [docs/mcp.md](docs/mcp.md).

---

## Documentation

| Document | Contents |
|---|---|
| [docs/self-hosting.md](docs/self-hosting.md) | Compose, environment, TLS proxy, volumes/backup, TTL, read-only hardening, what still talks to the internet, migration from the old two-container setup. |
| [docs/mcp.md](docs/mcp.md) | MCP endpoint, client configs, bearer token, local UI mirror, scene store behaviour, troubleshooting. |
| [plans/](plans/) | Implementation plans, including the design notes behind this release. |


---

## TLS / reverse proxy

Everything is served on container port `80`; terminate TLS in front of it and keep two things intact:

- forward `Upgrade`/`Connection` (websocket collaboration on `/socket.io/`), and
- leave `/mcp-ui/**` response headers alone — the MCP App iframe needs
  `Access-Control-Allow-Origin: *` and `Cross-Origin-Resource-Policy: cross-origin`.

Caddy needs nothing but `reverse_proxy 127.0.0.1:3030`. An nginx example, plus notes on rate-limiting
`/mcp`, lives in [docs/self-hosting.md](docs/self-hosting.md#tls--reverse-proxy). Remember to set
`FITDRAW_PUBLIC_URL` to the public origin, not the container address.

---

## What still leaves your network

`libraries.excalidraw.com` (the Library, on purpose), `raw.githubusercontent.com` (installing a
library from a PR), and Excalidraw's own Firebase project, which still backs live-room scene
persistence and image uploads. Everything else — the MCP UI's whole dependency graph included — is
served by the container. Details and the migration path:
[docs/self-hosting.md](docs/self-hosting.md#what-still-talks-to-the-internet).

---

## License

FitDraw is a distribution of [Excalidraw](https://github.com/excalidraw/excalidraw), which is [MIT licensed](https://github.com/excalidraw/excalidraw/blob/master/LICENSE). The Dockerfile and patches in this repository are also MIT licensed.

<!-- footer -->
---

## 🧑‍💻 Consulting and technical support
* For personal support and queries, please submit a new issue to have it addressed.
* For commercial related questions, please [**contact me**][ivancarlos] for consulting costs.

[cc]: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/adding-a-code-of-conduct-to-your-project
[contributing]: https://docs.github.com/en/articles/setting-guidelines-for-repository-contributors
[security]: https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository
[support]: https://docs.github.com/en/articles/adding-support-resources-to-your-project
[it]: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository#configuring-the-template-chooser
[prt]: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository
[funding]: https://docs.github.com/en/articles/displaying-a-sponsor-button-in-your-repository
[ivancarlos]: https://ivancarlos.me
