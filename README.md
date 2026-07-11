# FitDraw

**A cleaned, white-label distribution of [Excalidraw](https://github.com/excalidraw/excalidraw)** — the open-source virtual whiteboard for sketching hand-drawn diagrams. FitDraw strips all branding, promotional links, sign-up nudges, social media buttons, analytics, and collaboration upsells from the UI, leaving only the drawing tool.

---

## What gets removed

| UI Element | Location | Method |
|---|---|---|
| Excalidraw logo / home button | Top-left header | CSS `a[href="https://excalidraw.com"]` |
| Sign up / Sign in / Login buttons | Header & sidebar | CSS + JS: `aria-label`, `href` patterns |
| Excalidraw+ / Plus / Upgrade | Sidebar & toolbar | CSS + JS: `aria-label`, `href` |
| Comments tab | Sidebar (Radix UI tab) | CSS `[id$="-trigger-comments"]` + JS |
| Presentation tab | Sidebar (Radix UI tab) | CSS `[id$="-trigger-presentation"]` + JS |
| GitHub link | Sidebar | CSS + JS: `href*="github.com/excalidraw"` |
| Twitter / X "Follow us" | Sidebar | CSS + JS: `href*="twitter.com"`, `href*="x.com"` |
| Discord invite | Sidebar | CSS + JS: `href*="discord.gg"` |
| Simple Analytics tracking | `<script>` injection | 3-layer defense (see below) |

---

## How it works

FitDraw is built on top of the official [`excalidraw/excalidraw:latest`](https://hub.docker.com/r/excalidraw/excalidraw) Docker image. The [`Dockerfile`](Dockerfile) applies **four layers of patches** at build time, without touching the Excalidraw source code:

### Layer 1 — Static CSS ([`fitdraw.css`](Dockerfile:10-93))

A CSS file targeting elements by stable HTML attributes (`aria-label`, `href`, `title`, `id` suffix, `data-testid`). Because Excalidraw uses React with hashed class names, attribute selectors are used instead of class names. The CSS applies instantly on page load — no flicker.

```css
/* Example: hide the Excalidraw logo */
a[href="https://excalidraw.com"],
a[href="https://excalidraw.com"] * { display: none !important; }

/* Example: hide Radix UI tabs by stable ID suffix */
[id$="-trigger-comments"],
[id$="-trigger-presentation"] { display: none !important; }
```

### Layer 2 — JavaScript MutationObserver ([`fitdraw.js`](Dockerfile:98-248))

A self-executing script that:

- Runs `hideAll()` in waves (0 ms, 800 ms, 2 s, 5 s after `DOMContentLoaded`) to catch elements rendered after initial paint.
- Installs a [`MutationObserver`](https://developer.mozilla.org/en-US/docs/Web/API/MutationObserver) on `document.body` that re-applies hiding whenever React re-renders the DOM.
- Scans for and removes any `<script>` tags loading from `simpleanalyticscdn.com` or `sa.simpleanalytics` — both on page load and via the observer.

### Layer 3 — Build-time `sed` scrub ([Dockerfile:253-257](Dockerfile:253))

Before the image is finalized, a `find ... -exec sed` pass replaces every occurrence of `simpleanalyticscdn.com` and `sa.simpleanalytics` in all `.js` bundles with `__BLOCKED__.invalid`. This prevents the analytics code from ever being loaded, even if the JS runtime defenses are bypassed.

### Layer 4 — Content Security Policy ([Dockerfile:264](Dockerfile:264))

A `<meta>` tag injected into `index.html` restricts `script-src` to `'self'`, `'unsafe-inline'`, `'unsafe-eval'`, and `blob:`. This blocks **all external scripts** from loading — including any analytics domains that might slip through the other layers.

```html
<meta http-equiv="Content-Security-Policy"
      content="script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:;">
```

---

## Architecture

```
┌──────────────────────────────────────────┐
│                 Browser                   │
│  ┌────────────────────────────────────┐  │
│  │   fitdraw.css  (instant CSS hide)  │  │
│  │   fitdraw.js   (MutationObserver)  │  │
│  │   CSP meta     (block ext scripts) │  │
│  └────────────────────────────────────┘  │
│                    │                      │
│         https://fitdraw.example.com:3030  │
└────────────────────┬─────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────┐
│            Docker Host                    │
│                                           │
│  ┌──────────────────┐  ┌───────────────┐ │
│  │ desenho-frontend  │  │ desenho-backend│ │
│  │ (FitDraw / nginx) │  │ (collab server)│ │
│  │    port :3030     │  │   port :8082   │ │
│  └────────┬─────────┘  └───────┬───────┘ │
│           │                     │          │
│           └───── WebSocket ────┘          │
│               (patched at runtime)        │
└──────────────────────────────────────────┘
```

---

## Quick start

### Option A — Pull the pre-built image

```bash
docker pull ghcr.io/ivancarlosti/fitdraw:latest
docker run -d \
  --name fitdraw \
  -p 3030:80 \
  -e VITE_APP_WS_SERVER_URL=https://your-collab-server.example.com \
  ghcr.io/ivancarlosti/fitdraw:latest
```

> **Note:** The pre-built image does **not** include the WebSocket URL runtime patching built into the `docker-compose.yml`. If you need real-time collaboration, use the `docker-compose.yml` approach below, or override the entrypoint as shown in the compose file.

### Option B — Build from source

```bash
git clone https://github.com/ivancarlosti/fitdraw.git
cd fitdraw

# Build and tag the image
docker build -t fitdraw:latest .

# Run with the runtime WebSocket patch
docker run -d \
  --name fitdraw \
  -p 3030:80 \
  -e VITE_APP_WS_SERVER_URL=https://your-collab-server.example.com \
  --entrypoint /bin/sh \
  fitdraw:latest \
  -c "find /usr/share/nginx/html/ -type f -name '*.js' \
        -exec sed -i 's|https://oss-collab.excalidraw.com|\${VITE_APP_WS_SERVER_URL}|g' {} + && \
      nginx -g 'daemon off;'"
```

### Option C — Full stack with collaboration (docker compose)

```bash
cd docker
# Edit docker-compose.yml to set VITE_APP_WS_SERVER_URL to your domain
docker compose up -d
```

This starts both:
- **FitDraw frontend** on `http://localhost:3030`
- **Excalidraw Room** collaboration backend on `http://localhost:8082`

---

## WebSocket collaboration patching

The Excalidraw frontend is pre-built with `https://oss-collab.excalidraw.com` hardcoded as the WebSocket endpoint. The `docker-compose.yml` overrides the container entrypoint to perform a runtime `sed` pass:

```yaml
entrypoint: /bin/sh
command: >
  -c "find /usr/share/nginx/html/ -type f -name '*.js'
        -exec sed -i \"s|https://oss-collab.excalidraw.com|$${VITE_APP_WS_SERVER_URL}|g\" {} + &&
      nginx -g 'daemon off;'"
```

| Variable | Purpose | Example |
|---|---|---|
| `VITE_APP_WS_SERVER_URL` | Replaces the hardcoded collaboration server URL in all JS bundles | `https://fitdraw.example.com` |
| `VITE_APP_PLUS_APP_URL` | Set to `false` to disable cloud workspace export functions | `false` |

The `$$` syntax is Docker Compose escaping — it passes a literal `$` to the shell inside the container so the variable resolves at container start, not at Compose parse time.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `VITE_APP_WS_SERVER_URL` | For collab | (Excalidraw public server) | WebSocket URL for real-time collaboration |
| `VITE_APP_PLUS_APP_URL` | No | (Excalidraw Plus URL) | Set to `false` to disable Plus integration |

---

## Files

| File | Purpose |
|---|---|
| [`Dockerfile`](Dockerfile) | Builds the FitDraw image from `excalidraw/excalidraw:latest` |
| [`docker/docker-compose.yml`](docker/docker-compose.yml) | Full stack: FitDraw frontend + collaboration backend |
| `fitdraw.css` | Generated at build time — CSS hiding rules |
| `fitdraw.js` | Generated at build time — JS MutationObserver + analytics blocker |

---

## License

FitDraw is a distribution of [Excalidraw](https://github.com/excalidraw/excalidraw), which is [MIT licensed](https://github.com/excalidraw/excalidraw/blob/master/LICENSE). The Dockerfile and patches in this repository are also MIT licensed.
