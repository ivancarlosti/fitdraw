#!/bin/sh
# Fitdraw container entrypoint.
#
# 1. Validate FITDRAW_PUBLIC_URL (used by the MCP export link).
# 2. Patch the MCP App bundle on a writable copy under /tmp, so /opt can stay
#    immutable (the container works with --read-only).
# 3. Hand PID 1 over to the supervisor, which runs nginx + the three node
#    services.
set -eu

log() {
  echo "[entrypoint] $*"
}

# nginx must resolve its worker user; UID/GID defaults are baked into the image.
: "${FITDRAW_UID:=10001}"
: "${FITDRAW_GID:=10001}"
: "${SCENE_DATA_DIR:=/var/lib/fitdraw/scenes}"
export FITDRAW_UID FITDRAW_GID SCENE_DATA_DIR

if [ -z "${FITDRAW_PUBLIC_URL:-}" ]; then
  log "ERROR: FITDRAW_PUBLIC_URL is required (the origin users open in a browser)."
  log "       docker run -e FITDRAW_PUBLIC_URL=http://localhost:3030 -p 3030:80 fitdraw"
  log "       docker compose (in docker/) reads it from .env — see docker/.env.example"
  exit 1
fi

# Trailing slashes would produce //#json= links.
FITDRAW_PUBLIC_URL="${FITDRAW_PUBLIC_URL%/}"
export FITDRAW_PUBLIC_URL

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$SCENE_DATA_DIR"
  # A named volume mounted over the image path starts out owned by root.
  if [ -d "$SCENE_DATA_DIR" ] && [ "$(stat -c %u "$SCENE_DATA_DIR")" != "$FITDRAW_UID" ]; then
    chown -R "$FITDRAW_UID:$FITDRAW_GID" "$SCENE_DATA_DIR" 2>/dev/null || true
  fi
fi

log "patching MCP App for $FITDRAW_PUBLIC_URL"
rm -rf /tmp/mcp
cp -a /opt/mcp /tmp/mcp
if ! node /opt/selfhost/patch-mcp.mjs --app /tmp/mcp; then
  log "ERROR: patching the MCP App failed — see the message above"
  exit 1
fi

log "starting supervisor"
exec node /opt/selfhost/supervisor.mjs
