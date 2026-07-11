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

/* Hide Comments & Presentation Radix UI sidebar tabs (dynamic IDs like radix-:rX:-trigger-*) */
[id$="-trigger-comments"],
[id$="-trigger-presentation"],
[aria-controls$="-content-comments"],
[aria-controls$="-content-presentation"],

/* Hide Sign up / Sign in / Login buttons (header & sidebar) */
[aria-label*="Sign up" i],
[aria-label*="Sign in" i],
[aria-label*="Log in" i],
[aria-label*="Login" i],

/* Hide Library / "Your library" upsell */
a[href*="plus.excalidraw.com" i],
[href*="plus.excalidraw.com" i],

/* Hide GitHub link (sidebar) */
a[href*="github.com/excalidraw" i],
a[href*="github.com/excalidraw" i] *,
[aria-label*="GitHub" i],
[title*="GitHub" i],

/* Hide Twitter / X  / "Follow us" (sidebar) */
a[href*="twitter.com/excalidraw" i],
a[href*="x.com/excalidraw" i],
a[href*="x.com/excalidraw" i] *,
[aria-label*="Twitter" i],
[aria-label*="Follow us" i],
[title*="Twitter" i],
[title*="Follow us" i],

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

    /* -- Comments & Presentation Radix UI tabs (dynamic IDs) -- */
    '[id$="-trigger-comments"]',
    '[id$="-trigger-presentation"]',
    '[aria-controls$="-content-comments"]',
    '[aria-controls$="-content-presentation"]',

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

    /* -- GitHub -- */
    'a[href*="github.com/excalidraw"]',
    '[aria-label*="GitHub"]',
    '[title*="GitHub"]',

    /* -- Twitter / X / Follow us -- */
    'a[href*="twitter.com/excalidraw"]',
    'a[href*="x.com/excalidraw"]',
    '[aria-label*="Twitter"]',
    '[aria-label*="Follow us"]',
    '[title*="Twitter"]',
    '[title*="Follow us"]',

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

  /* --- run in waves to catch late-rendered elements --- */
  function scheduleRuns() {
    hideAll();
    setTimeout(hideAll, 800);
    setTimeout(hideAll, 2000);
    setTimeout(hideAll, 5000);
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
        observer = new MutationObserver(function (mutations) {
          hideAll();
          /* Also strip any Simple Analytics scripts injected after load */
          for (var m = 0; m < mutations.length; m++) {
            var added = mutations[m].addedNodes;
            for (var a = 0; a < added.length; a++) {
              var node = added[a];
              if (node.tagName === 'SCRIPT' && node.src &&
                  (node.src.indexOf('simpleanalytics') !== -1 ||
                   node.src.indexOf('sa.simpleanalytics') !== -1)) {
                node.parentNode && node.parentNode.removeChild(node);
              }
            }
          }
        });
        observer.observe(document.body, { childList: true, subtree: true });
      } else {
        setTimeout(startObserving, 50);
      }
    }

    startObserving();
  }

  /* --- Strip any existing Simple Analytics <script> tags on load --- */
  function stripSimpleAnalytics() {
    var scripts = document.getElementsByTagName('script');
    for (var i = scripts.length - 1; i >= 0; i--) {
      var src = scripts[i].src || '';
      if (src.indexOf('simpleanalytics') !== -1 ||
          src.indexOf('sa.simpleanalytics') !== -1) {
        scripts[i].parentNode && scripts[i].parentNode.removeChild(scripts[i]);
      }
    }
  }
  stripSimpleAnalytics();
  setTimeout(stripSimpleAnalytics, 1000);
  setTimeout(stripSimpleAnalytics, 3000);
})();
JSEOF

# ---------------------------------------------------------------------------
# 3. Build-time scrub: remove Simple Analytics references from JS bundles
# ---------------------------------------------------------------------------
RUN echo "[FitDraw] Scrubbing Simple Analytics from JS bundles..." && \
    find /usr/share/nginx/html -type f -name '*.js' \
      -exec sed -i 's|simpleanalyticscdn\.com|__BLOCKED__.invalid|gi' {} + && \
    find /usr/share/nginx/html -type f -name '*.js' \
      -exec sed -i 's|sa\.simpleanalytics|__BLOCKED__.invalid|gi' {} +

# ---------------------------------------------------------------------------
# 4. Inject CSS, JS, and CSP meta tag into every .html file
# ---------------------------------------------------------------------------
RUN for html in $(find /usr/share/nginx/html -maxdepth 1 -name '*.html' -type f 2>/dev/null); do \
      echo "[FitDraw] Patching ${html}"; \
      sed -i "s|</head>|<meta http-equiv=\"Content-Security-Policy\" content=\"script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:;\">\n<link rel=\"stylesheet\" href=\"/fitdraw.css\">\n<script defer src=\"/fitdraw.js\"></script>\n</head>|" "$html"; \
    done
