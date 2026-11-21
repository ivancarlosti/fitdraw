# ============================================================================
# Fitdraw — all-in-one image
#
#   stage room      pruned excalidraw-room runtime (pinned by digest)
#   stage mcp       excalidraw-mcp release asset (pinned by version + sha256)
#   stage frontend  Excalidraw bundle with remote hosts scrubbed
#   final           nginx + node services under one supervisor, one port
#
# The pins below are mirrored in .excalidraw-version / .excalidraw-room-digest /
# .excalidraw-mcp so .github/workflows/excalidraw_update.yml can bump them all in
# a single commit, and .github/workflows/build.yml fails if they drift apart.
# ============================================================================

ARG NODE_IMAGE=node:22-alpine
ARG EXCALIDRAW_ROOM_DIGEST=sha256:2fe999f9be4379e3ee282fc45d75d84a691a6383dde33544514cc395287c7a70
ARG MCP_VERSION=v0.3.2
ARG MCP_VERSION_SHA256=2b494012b5fee5937f9f7b86f04a76cc4a91ec843ee3339b93e4e15e415274ff
ARG MCP_UI_MODE=mirror

# ---------------------------------------------------------------------------
# Collaboration room. The published image ships 123 MB of dev tooling
# (typescript, eslint, prettier, ts-node-dev) plus node 12, but only dist/ and
# four runtime dependencies are needed. Versions are pinned to the ones the
# image's yarn.lock resolved, so behaviour is unchanged on a modern node.
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 excalidraw/excalidraw-room@${EXCALIDRAW_ROOM_DIGEST} AS room-source

FROM ${NODE_IMAGE} AS room
WORKDIR /room
COPY --from=room-source /excalidraw-room/dist ./dist
COPY --from=room-source /excalidraw-room/package.json ./package.json
RUN node -e "const fs=require('node:fs');const pkg=JSON.parse(fs.readFileSync('package.json','utf8'));const pinned={'express':'4.17.1','socket.io':'4.6.1','debug':'4.3.1','dotenv':'10.0.0'};const dev={};for(const [name,range] of Object.entries(pkg.dependencies)){if(!(name in pinned))dev[name]=range;}pkg.dependencies={...pinned};pkg.devDependencies=dev;pkg.optionalDependencies={};pkg.scripts={start:'node dist/index.js'};fs.writeFileSync('package.json',JSON.stringify(pkg,null,2)+'\n');" \
 && npm install --omit=dev --no-audit --no-fund --loglevel=error \
 && node -e "require.resolve('express');require.resolve('socket.io');require.resolve('debug');require.resolve('dotenv')" \
 && rm -f package-lock.json && rm -rf /root/.npm

# ---------------------------------------------------------------------------
# MCP server + its single-file UI. The UI imports React 19, Excalidraw 0.18 and
# morphdom from esm.sh; selfhost/mirror-mcp-ui.mjs crawls that graph into
# /mcp-ui/vendor with relative specifiers, so the iframe never leaves our origin.
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS mcp
ARG MCP_VERSION
ARG MCP_VERSION_SHA256
ARG MCP_UI_MODE
RUN apk add --no-cache curl unzip
WORKDIR /mcp
RUN curl -fsSL --retry 3 --retry-delay 2 -o /tmp/app.mcpb \
      "https://github.com/excalidraw/excalidraw-mcp/releases/download/${MCP_VERSION}/excalidraw-mcp-app.mcpb" \
 && echo "${MCP_VERSION_SHA256}  /tmp/app.mcpb" | sha256sum -c - \
 && unzip -q /tmp/app.mcpb -d /mcp \
 && rm -f /tmp/app.mcpb \
 && rm -rf /mcp/docs /mcp/scripts /mcp/.vercel /mcp/README.md /mcp/bun.lock \
 && test -s /mcp/dist/index.js && test -s /mcp/dist/mcp-app.html && test -s /mcp/package.json
COPY selfhost/mirror-mcp-ui.mjs /tmp/mirror-mcp-ui.mjs
RUN node /tmp/mirror-mcp-ui.mjs --app /mcp/dist/mcp-app.html --out /mcp-ui --mode "${MCP_UI_MODE}" \
 && rm -f /tmp/mirror-mcp-ui.mjs \
 && test -s /mcp-ui/manifest.json \
 && if [ "${MCP_UI_MODE}" = "mirror" ]; then ! grep -q 'esm\.sh' /mcp/dist/mcp-app.html; fi

# ---------------------------------------------------------------------------
# Frontend: rewrite every Excalidraw-owned host (Library excepted), drop the
# 23 MB of sourcemaps and the excalidraw.com SEO files. scrub.mjs fails the
# build if a forbidden host survives or the Library wiring disappears.
# ---------------------------------------------------------------------------
FROM excalidraw/excalidraw:latest AS excalidraw-dist

FROM ${NODE_IMAGE} AS frontend
COPY --from=excalidraw-dist /usr/share/nginx/html /html
COPY selfhost/scrub.mjs /scrub.mjs
RUN node /scrub.mjs /html

FROM excalidraw/excalidraw:latest


ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_DATE=unknown
ARG MCP_VERSION=v0.3.2
ARG EXCALIDRAW_ROOM_DIGEST=sha256:2fe999f9be4379e3ee282fc45d75d84a691a6383dde33544514cc395287c7a70
ARG MCP_UI_MODE=mirror

LABEL org.opencontainers.image.title="Fitdraw" \
      org.opencontainers.image.description="White-label Excalidraw with collaboration, an MCP server, an encrypted scene store and a fully local MCP UI" \
      org.opencontainers.image.source="https://github.com/ivancarlosti/fitdraw" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/excalidraw/excalidraw:latest" \
      fitdraw.mcp.version="${MCP_VERSION}" \
      fitdraw.mcp.ui.mode="${MCP_UI_MODE}" \
      fitdraw.room.digest="${EXCALIDRAW_ROOM_DIGEST}"

ENV NODE_ENV=production \
    FITDRAW_UID=10001 \
    FITDRAW_GID=10001 \
    SCENE_DATA_DIR=/var/lib/fitdraw/scenes \
    SCENE_TTL_DAYS=30 \
    ENABLE_MCP=1 \
    ENABLE_ROOM=1 \
    ENABLE_STORE=1

# node runs the supervisor, the MCP server, the room and the scene store.
RUN apk add --no-cache nodejs \
 && node -e "const [major,minor]=process.versions.node.split('.').map(Number);if(major<20||(major===20&&minor<11)){console.error('node '+process.versions.node+' is too old, need >=20.11');process.exit(1)};console.log('using node '+process.versions.node)" \
 && addgroup -S -g "${FITDRAW_GID}" fitdraw \
 && adduser -S -D -H -u "${FITDRAW_UID}" -G fitdraw fitdraw \
 && mkdir -p "${SCENE_DATA_DIR}" /opt/selfhost/scene-store \
 && chown -R fitdraw:fitdraw /var/lib/fitdraw

# Serve the scrubbed bundle, never the base image's original tree. COPY merges
# directories, so the old html root (with its 23 MB of sourcemaps) is removed
# first.
RUN rm -rf /usr/share/nginx/html /etc/nginx/conf.d/default.conf
COPY --from=frontend /html /usr/share/nginx/html
COPY --from=room /room /opt/room
COPY --from=mcp /mcp /opt/mcp
COPY --from=mcp /mcp-ui /opt/mcp-ui
COPY selfhost/nginx/00-fitdraw-map.conf /etc/nginx/conf.d/00-fitdraw-map.conf
COPY selfhost/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY selfhost/scene-store/server.mjs /opt/selfhost/scene-store/server.mjs
COPY selfhost/patch-mcp.mjs selfhost/supervisor.mjs selfhost/healthcheck.mjs /opt/selfhost/
COPY selfhost/entrypoint.sh /opt/selfhost/entrypoint.sh
RUN chmod 0755 /opt/selfhost/entrypoint.sh

# The supervisor owns stdout/stderr, so nginx must use the inherited descriptors
# instead of the image's /dev/stdout symlinks (opening those fails with ENXIO
# when the container's stdio is a pipe). /tmp as pid path keeps --read-only happy.
RUN sed -i \
      -e 's|^error_log .*|error_log stderr warn;|' \
      -e 's|^pid .*|pid /tmp/nginx.pid;|' \
      -e 's|^\( *\)access_log  /var/log/nginx/access.log.*|\1access_log off;|' \
      /etc/nginx/nginx.conf \
 && grep -q 'error_log stderr warn;' /etc/nginx/nginx.conf \
 && ln -sf /dev/null /var/log/nginx/error.log \
 && ln -sf /dev/null /var/log/nginx/access.log


# ============================================================================
# FitDraw — Excalidraw fork with promotional/branding UI elements hidden
# ============================================================================

# ---------------------------------------------------------------------------
# 1. Custom CSS — static hiding via attribute selectors (aria-label, href, title)
# ---------------------------------------------------------------------------
RUN cat > /usr/share/nginx/html/fitdraw.css << 'CSSEOF'
/* Hide Excalidraw logo / home button in the top bar (scrubbed builds link to "/") */
a[href="https://excalidraw.com"],
a[href="https://excalidraw.com"] *,
a[href="/"],
a[href="/"] *,

/* Hide Excalidraw+ / Plus / Upgrade — toolbar & sidebar */
[aria-label*="Plus" i],
[aria-label*="plus" i],
[aria-label*="Upgrade" i],
[aria-label*="upgrade" i],
[aria-label*="Pro" i],

/* Hide Comments toggle button */
[aria-label*="Comment" i],
[aria-label*="comment" i],

/* Hide Presentation / slides button */
[aria-label*="Presentation" i],
[aria-label*="presentation" i],

/* Hide AI Badge on menu items */
.DropDownMenuItemBadge,

/* Hide AI Magic Frame button */
[data-testid="toolbar-magicframe"],

/* Hide Comments & Presentation Radix UI sidebar tabs (dynamic IDs like radix-:rX:-trigger-*) */
[id$="-trigger-comments"],
[id$="-trigger-presentation"],
[aria-controls$="-content-comments"],
[aria-controls$="-content-presentation"],

/* Hide Text-to-Diagram AI tab in Mermaid dialog */
[id$="-trigger-text-to-diagram"],
[aria-controls$="-content-text-to-diagram"],

/* Hide Sign up / Sign in / Login buttons (header & sidebar) */
[aria-label*="Sign up" i],
[aria-label*="Sign in" i],
[aria-label*="Log in" i],
[aria-label*="Login" i],

/* Hide Library / "Your library" upsell */
a[href*="plus.excalidraw.com" i],
[href*="plus.excalidraw.com" i],

/* Hide Excalidraw+ promo card on Save/Export screen */
.Card:has(.ExcalidrawLogo) {
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
  width: 0 !important;
  height: 0 !important;
  overflow: hidden !important;
  position: absolute !important;
  clip: rect(0,0,0,0) !important;
}

/* Hide "Shareable link" card on Save/Export screen */
.Card:has([aria-label="Export to Link"]) {
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
  width: 0 !important;
  height: 0 !important;
  overflow: hidden !important;
  position: absolute !important;
  clip: rect(0,0,0,0) !important;
}

/* Hide any menu item containing an AI badge */
.radix-menu-item:has(.DropDownMenuItemBadge) {
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
  width: 0 !important;
  height: 0 !important;
  overflow: hidden !important;
  position: absolute !important;
  clip: rect(0,0,0,0) !important;
}

/* Hide top-right Share button container */
.excalidraw-ui-top-right,

/* Hide Discord invite (sidebar) */
a[href*="discord.gg" i],
a[href*="discord.com/invite" i],
a[href*="discord" i] *,
[aria-label*="Discord" i],
[title*="Discord" i],

/* Generic upsell / promo containers */
[data-testid*="plus" i],
[data-testid*="upgrade" i],
[data-testid*="pro" i],
[data-testid*="comment" i],
[data-testid*="presentation" i],

/* Any link with signup/login paths */
a[href*="sign-up" i],
a[href*="signup" i],
a[href*="sign-in" i],
a[href*="signin" i],
a[href*="login" i],
a[href*="log-in" i]
{
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
  width: 0 !important;
  height: 0 !important;
  overflow: hidden !important;
  position: absolute !important;
  clip: rect(0,0,0,0) !important;
}
CSSEOF

# ---------------------------------------------------------------------------
# 2. JavaScript patch — MutationObserver fallback for dynamically rendered UI
# ---------------------------------------------------------------------------
RUN cat > /usr/share/nginx/html/fitdraw.js << 'JSEOF'
(function () {
  'use strict';

  var HIDE_SELECTORS = [
    /* -- Logo / home -- */
    'a[href="https://excalidraw.com"]',
    'a[href="/"]',

    /* -- Plus / Upgrade / Pro -- */
    '[aria-label*="Plus"]',
    '[aria-label*="Upgrade"]',
    '[aria-label*="Pro"]',
    'a[href*="plus.excalidraw.com"]',

    /* -- Comments -- */
    '[aria-label*="Comment"]',
    '[aria-label*="comment"]',

    /* -- Presentation -- */
    '[aria-label*="Presentation"]',
    '[aria-label*="presentation"]',
    '[data-testid*="presentation"]',

    /* -- Share button container (top bar) -- */
    '.excalidraw-ui-top-right',

    /* -- AI Badge and menu items -- */
    '.DropDownMenuItemBadge',
    '.radix-menu-item:has(.DropDownMenuItemBadge)',

    /* -- AI Magic Frame (toolbar) -- */
    '[data-testid="toolbar-magicframe"]',

    /* -- Comments & Presentation Radix UI tabs (dynamic IDs) -- */
    '[id$="-trigger-comments"]',
    '[id$="-trigger-presentation"]',
    '[aria-controls$="-content-comments"]',
    '[aria-controls$="-content-presentation"]',

    /* -- Text-to-Diagram AI tab (Mermaid dialog) -- */
    '[id$="-trigger-text-to-diagram"]',
    '[aria-controls$="-content-text-to-diagram"]',

    /* -- Sign up / Sign in / Login -- */
    '[aria-label*="Sign up"]',
    '[aria-label*="Sign in"]',
    '[aria-label*="Log in"]',
    '[aria-label*="Login"]',
    'a[href*="sign-up"]',
    'a[href*="signup"]',
    'a[href*="sign-in"]',
    'a[href*="signin"]',
    'a[href*="login"]',
    'a[href*="log-in"]',

    /* -- Discord -- */
    'a[href*="discord.gg"]',
    'a[href*="discord.com/invite"]',
    '[aria-label*="Discord"]',
    '[title*="Discord"]',

    /* -- Data attributes (generic) -- */
    '[data-testid*="plus"]',
    '[data-testid*="upgrade"]',
    '[data-testid*="pro"]',
    '[data-testid*="comment"]'
  ];

  var HIDE_STYLE =
    'display:none !important;' +
    'visibility:hidden !important;' +
    'opacity:0 !important;' +
    'pointer-events:none !important;' +
    'width:0 !important;' +
    'height:0 !important;' +
    'overflow:hidden !important;' +
    'position:absolute !important;' +
    'clip:rect(0,0,0,0) !important;';

  function hideAll() {
    for (var s = 0; s < HIDE_SELECTORS.length; s++) {
      try {
        var nodes = document.querySelectorAll(HIDE_SELECTORS[s]);
        for (var n = 0; n < nodes.length; n++) {
          nodes[n].style.cssText = HIDE_STYLE;
          nodes[n].setAttribute('aria-hidden', 'true');
          nodes[n].setAttribute('hidden', '');
        }
      } catch (_) { /* selector error — ignore */ }
    }
  }

  /* --- patch: change GitHub link to FitDraw repo --- */
  function patchGitHubLink() {
    try {
      var ghLinks = document.querySelectorAll('a[href*="github.com/excalidraw"]');
      for (var i = 0; i < ghLinks.length; i++) {
        ghLinks[i].setAttribute('href', 'https://github.com/ivancarlosti/fitdraw');
        ghLinks[i].setAttribute('aria-label', 'FitDraw on GitHub');
        ghLinks[i].setAttribute('title', 'FitDraw on GitHub');
      }
    } catch (_) {}
  }

  /* --- patch: change Twitter/X link to ivancarlos --- */
  function patchTwitterLink() {
    try {
      var twLinks = document.querySelectorAll('a[href*="twitter.com/excalidraw"], a[href*="x.com/excalidraw"]');
      for (var i = 0; i < twLinks.length; i++) {
        twLinks[i].setAttribute('href', 'https://x.com/ivancarlos');
        twLinks[i].setAttribute('aria-label', 'Follow @ivancarlos on X');
        twLinks[i].setAttribute('title', 'Follow @ivancarlos on X');
      }
    } catch (_) {}
  }

  /* --- patch: set page title to Fitdraw Whiteboard --- */
  function patchPageTitle() {
    try {
      document.title = 'Fitdraw Whiteboard';
    } catch (_) {}
  }

  /* --- patch: hide Excalidraw+ promo card on Save/Export screen --- */
  function hideExcalidrawPlusCard() {
    try {
      var logos = document.querySelectorAll('.ExcalidrawLogo');
      for (var i = 0; i < logos.length; i++) {
        var card = logos[i].closest('.Card');
        if (card) {
          card.style.cssText = HIDE_STYLE;
          card.setAttribute('aria-hidden', 'true');
          card.setAttribute('hidden', '');
        }
      }
    } catch (_) {}
  }

  /* --- apply all patches --- */
  function applyPatches() {
    patchGitHubLink();
    patchTwitterLink();
    patchPageTitle();
    hideExcalidrawPlusCard();
  }

  /* --- run in waves to catch late-rendered elements --- */
  function scheduleRuns() {
    hideAll();
    applyPatches();
    setTimeout(hideAll, 800);
    setTimeout(applyPatches, 800);
    setTimeout(hideAll, 2000);
    setTimeout(applyPatches, 2000);
    setTimeout(hideAll, 5000);
    setTimeout(applyPatches, 5000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleRuns);
  } else {
    scheduleRuns();
  }

  /* --- MutationObserver: keep hiding as React re-renders --- */
  if (typeof MutationObserver !== 'undefined') {
    var observer = null;

    function startObserving() {
      if (document.body) {
        observer = new MutationObserver(function () {
          hideAll();
          applyPatches();
        });
        observer.observe(document.body, { childList: true, subtree: true });
      } else {
        setTimeout(startObserving, 50);
      }
    }

    startObserving();
  }
})();
JSEOF

# ---------------------------------------------------------------------------
# 3. Strip Simple Analytics inline <script> block from HTML
# ---------------------------------------------------------------------------
RUN for html in $(find /usr/share/nginx/html -maxdepth 1 -name '*.html' -type f 2>/dev/null); do \
      echo "[FitDraw] Stripping Simple Analytics from ${html}"; \
      sed -i '/<script>/,/<\/script>/{/simpleanalyticscdn\.com/!b;:a;N;/<\/script>/!ba;d;}' "$html"; \
    done

# ---------------------------------------------------------------------------
# 4. Inject CSS, JS, and CSP meta tag into every .html file
# ---------------------------------------------------------------------------
RUN for html in $(find /usr/share/nginx/html -maxdepth 1 -name '*.html' -type f 2>/dev/null); do \
      echo "[FitDraw] Patching ${html}"; \
      sed -i "s|</head>|<meta http-equiv=\"Content-Security-Policy\" content=\"script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:;\">\n<link rel=\"stylesheet\" href=\"/fitdraw.css\">\n<script defer src=\"/fitdraw.js\"></script>\n</head>|" "$html"; \
    done

# ---------------------------------------------------------------------------
# 5. Build-time gate
#    The scrub stage already rewrote the upstream bundle; this re-checks the
#    final tree (including the files injected above) so a future base image that
#    reintroduces a host fails the build instead of leaking traffic.
# ---------------------------------------------------------------------------
RUN set -eu; \
    hits="$(grep -rhoE 'https?://([a-z0-9-]+\.)*excalidraw\.com' /usr/share/nginx/html \
      --include='*.js' --include='*.html' --include='*.css' --include='*.json' --include='*.webmanifest' \
      | grep -v 'libraries\.excalidraw\.com' | sort -u || true)"; \
    if [ -n "${hits}" ]; then \
      echo "ERROR: forbidden Excalidraw hosts are still present:"; \
      echo "${hits}"; \
      exit 1; \
    fi; \
    if ! grep -rq 'libraries\.excalidraw\.com' /usr/share/nginx/html/assets; then \
      echo "ERROR: the Library URL disappeared from the bundle — scrub rules are stale"; \
      exit 1; \
    fi; \
    if ! grep -rq '"/api/v2/post/"' /usr/share/nginx/html/assets; then \
      echo "ERROR: the bundle does not point at the local scene store"; \
      exit 1; \
    fi; \
    echo "[FitDraw] host gate passed (Library kept, everything else local)"

# ---------------------------------------------------------------------------
# 6. Runtime surface: one public port, supervised processes, real health check.
#    FITDRAW_PUBLIC_URL is supplied at run time and documented in docs/mcp.md.
# ---------------------------------------------------------------------------
EXPOSE 80

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD ["node", "/opt/selfhost/healthcheck.mjs"]

ENTRYPOINT ["/opt/selfhost/entrypoint.sh"]

