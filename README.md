# FitDraw

**A clean, white-label distribution of [Excalidraw](https://github.com/excalidraw/excalidraw)** — the open-source virtual whiteboard for sketching hand-drawn diagrams.

FitDraw removes branding, promotional links, sign-up nudges, analytics, and collaboration upsells from the UI. Social links are redirected to FitDraw's own profiles, and the page title is set to **Fitdraw Whiteboard**.

---

## What's removed

- Excalidraw logo and home button
- Sign up / Sign in / Login buttons
- Excalidraw+ / Plus / Upgrade prompts
- Comments and Presentation tabs
- Discord invite
- Excalidraw+ promo card on the export dialog
- GitHub and Twitter/X links → redirected to FitDraw profiles

---

## Quick start

The easiest way to run FitDraw is with the provided Docker Compose file, which starts both the frontend and the collaboration backend.

```bash
git clone https://github.com/ivancarlosti/fitdraw.git
cd fitdraw/docker

# Edit docker-compose.yml and set VITE_APP_WS_SERVER_URL to your domain
docker compose up -d
```

This starts:
- **FitDraw frontend** on `http://localhost:3030`
- **Collaboration backend** on `http://localhost:8082`

### Environment variables

| Variable | Description |
|---|---|
| `VITE_APP_WS_SERVER_URL` | Your domain for WebSocket collaboration (e.g. `https://fitdraw.example.com`) |
| `VITE_APP_PLUS_APP_URL` | Set to `false` to disable cloud workspace export |

---

## License

FitDraw is a distribution of [Excalidraw](https://github.com/excalidraw/excalidraw), which is [MIT licensed](https://github.com/excalidraw/excalidraw/blob/master/LICENSE). The Dockerfile and patches in this repository are also MIT licensed.
