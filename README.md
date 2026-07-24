# FitDraw

**A clean, white-label distribution of [Excalidraw](https://github.com/excalidraw/excalidraw)** — the open-source virtual whiteboard for sketching hand-drawn diagrams.

FitDraw removes branding, promotional links, sign-up nudges, analytics, and collaboration upsells from the UI. Social links are redirected to FitDraw's own profiles, and the page title is set to **Fitdraw Whiteboard**.

<!-- buttons -->
[![Stars](https://img.shields.io/github/stars/ivancarlosti/ivancarlosti?label=⭐%20Stars&color=gold&style=flat)](https://github.com/ivancarlosti/ivancarlosti/stargazers)
[![Watchers](https://img.shields.io/github/watchers/ivancarlosti/ivancarlosti?label=Watchers&style=flat&color=red)](https://github.com/sponsors/ivancarlosti)
[![Forks](https://img.shields.io/github/forks/ivancarlosti/ivancarlosti?label=Forks&style=flat&color=ff69b4)](https://github.com/sponsors/ivancarlosti)
[![Downloads](https://img.shields.io/github/downloads/ivancarlosti/ivancarlosti/total?label=Downloads&color=success)](https://github.com/ivancarlosti/ivancarlosti/releases)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/ivancarlosti/ivancarlosti?label=Activity)](https://github.com/ivancarlosti/ivancarlosti/pulse)
[![GitHub Issues](https://img.shields.io/github/issues/ivancarlosti/ivancarlosti?label=Issues&color=orange)](https://github.com/ivancarlosti/ivancarlosti/issues)  
[![License](https://img.shields.io/github/license/ivancarlosti/ivancarlosti?label=License)](LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/ivancarlosti/ivancarlosti?label=Last%20Commit)](https://github.com/ivancarlosti/ivancarlosti/commits)
[![Security](https://img.shields.io/badge/Security-View%20Here-purple)](https://github.com/ivancarlosti/ivancarlosti/security)
[![Code of Conduct](https://img.shields.io/badge/Code%20of%20Conduct-2.1-4baaaa)](https://github.com/ivancarlosti/ivancarlosti?tab=coc-ov-file)
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

## Reverse proxy setup (collaboration)

If you're running FitDraw behind a reverse proxy (nginx, Traefik, Caddy, etc.), you need to route WebSocket traffic (`/socket.io/`) to the collaboration backend container on port `8082`. Without this, shared links won't sync.

**nginx example** — add this `location` block before your main `/` location:

```nginx
location /socket.io/ {
    proxy_pass http://127.0.0.1:8082;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
}
```

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

