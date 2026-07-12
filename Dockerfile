FROM excalidraw/excalidraw:latest

# ============================================================================
# FitDraw — Excalidraw fork with promotional/branding UI elements hidden
# ============================================================================

# ---------------------------------------------------------------------------
# 1. Custom CSS — static hiding via attribute selectors (aria-label, href, title)
# ---------------------------------------------------------------------------
RUN cat > /usr/share/nginx/html/fitdraw.css << 'CSSEOF'
/* Hide Excalidraw logo / home button in the top bar */
a[href="https://excalidraw.com"],
a[href="https://excalidraw.com"] *,

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
