#!/usr/bin/env bash
# Deploy RuView (WiFi-DensePose) on a QNAP NAS via Docker / Container Station.
# Safe to re-run: it removes any prior "ruview" container and recreates it with the
# same persisted API token + an auto-derived host allowlist, so re-runs "just work".
#
# Usage (run ON the NAS over SSH, or let Claude Code run it):
#   ./deploy-qnap.sh                                 # port 3010, simulated, token auth
#   PORT=3010 CSI_SOURCE=simulated ./deploy-qnap.sh
#   CSI_SOURCE=esp32 ./deploy-qnap.sh                # once your ESP32 streams to the NAS
#   RUVIEW_ALLOW_UNAUTHENTICATED=1 ./deploy-qnap.sh  # open on a trusted LAN (no token)
#
# Security: by default the server requires a bearer token because /ws/sensing streams
# live sensing frames (the image refuses to start otherwise — exit 64). This script
# generates a token on first run and persists it to $TOKEN_FILE so every re-run reuses
# it (clients keep working). It also sets SENSING_ALLOWED_HOSTS (DNS-rebinding defense,
# else browsers get HTTP 421) to this NAS's LAN IP + port automatically.
set -euo pipefail

PORT="${PORT:-3010}"                       # host port -> container 3000 (REST/UI)
WS_PORT="${WS_PORT:-3011}"                  # host port -> container 3001 (WebSocket)
CSI_SOURCE="${CSI_SOURCE:-simulated}"       # simulated | esp32 | wifi | auto
IMAGE="${IMAGE:-ruvnet/wifi-densepose:latest}"
NAME="${NAME:-ruview}"
TOKEN_FILE="${TOKEN_FILE:-$HOME/.ruview/api_token}"   # persisted API token

# --- locate docker (QNAP often hides it under Container Station) -------------
DOCKER=""
if command -v docker >/dev/null 2>&1; then
  DOCKER="$(command -v docker)"
else
  for p in \
    /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker \
    /share/ZFS530_DATA/.qpkg/container-station/bin/docker \
    /share/*/.qpkg/container-station/bin/docker; do
    [ -x "$p" ] && DOCKER="$p" && break
  done
fi
if [ -z "$DOCKER" ]; then
  echo "ERROR: docker not found. Enable Container Station, or set DOCKER=/path/to/docker." >&2
  exit 1
fi
echo ">> Using docker at: $DOCKER"

# --- report architecture (image is multi-arch: amd64 + arm64) ---------------
ARCH="$(uname -m)"
echo ">> NAS architecture: $ARCH"
case "$ARCH" in
  x86_64|amd64|aarch64|arm64) ;;
  *) echo "WARN: $ARCH may not have a matching image tag; continuing anyway." >&2 ;;
esac

# --- detect this NAS's primary LAN IP (used for the host allowlist) ----------
# Tolerant: BusyBox `hostname` (QNAP) lacks -I, so try `ip` first. Never let a
# failed probe abort the script (set -e + pipefail) — hence the trailing `|| true`.
IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
[ -z "$IP" ] && IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | cut -d/ -f1 | head -1 || true)"
[ -z "$IP" ] && IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
[ -z "$IP" ] && IP="$(hostname -i 2>/dev/null | awk '{print $1}' || true)"

# --- assemble container env -------------------------------------------------
RUN_ENV=( -e "CSI_SOURCE=${CSI_SOURCE}" )

# Auth posture: bearer token by default; opt out only on a trusted LAN.
if [ "${RUVIEW_ALLOW_UNAUTHENTICATED:-0}" = "1" ]; then
  echo ">> AUTH: UNAUTHENTICATED (RUVIEW_ALLOW_UNAUTHENTICATED=1) — open to anyone on the LAN"
  RUN_ENV+=( -e "RUVIEW_ALLOW_UNAUTHENTICATED=1" )
  TOKEN=""
else
  TOKEN="${RUVIEW_API_TOKEN:-}"
  if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
    TOKEN="$(cat "$TOKEN_FILE")"
    echo ">> AUTH: reusing API token from $TOKEN_FILE"
  fi
  if [ -z "$TOKEN" ]; then
    if command -v openssl >/dev/null 2>&1; then
      TOKEN="$(openssl rand -hex 32)"
    else
      TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
    mkdir -p "$(dirname "$TOKEN_FILE")"
    ( umask 077; printf '%s\n' "$TOKEN" > "$TOKEN_FILE" )
    chmod 600 "$TOKEN_FILE" 2>/dev/null || true
    echo ">> AUTH: generated a new API token, saved to $TOKEN_FILE"
  fi
  RUN_ENV+=( -e "RUVIEW_API_TOKEN=${TOKEN}" )
fi

# Host allowlist (DNS-rebinding defense). Without the NAS IP here, browsers get HTTP 421.
DEFAULT_HOSTS="localhost:${PORT},localhost,127.0.0.1:${PORT},127.0.0.1"
[ -n "$IP" ] && DEFAULT_HOSTS="${IP}:${PORT},${IP},${DEFAULT_HOSTS}"
ALLOWED_HOSTS="${SENSING_ALLOWED_HOSTS:-$DEFAULT_HOSTS}"
RUN_ENV+=( -e "SENSING_ALLOWED_HOSTS=${ALLOWED_HOSTS}" )
echo ">> Allowed hosts: ${ALLOWED_HOSTS}"

# Optional: real RuField signing seed (else the server uses a dev key + warns).
[ -n "${WDP_RUFIELD_SIGNING_SEED:-}" ] && RUN_ENV+=( -e "WDP_RUFIELD_SIGNING_SEED=${WDP_RUFIELD_SIGNING_SEED}" )

# --- pull, replace, run ------------------------------------------------------
echo ">> Pulling $IMAGE ..."
"$DOCKER" pull "$IMAGE"

echo ">> Removing any existing '$NAME' container ..."
"$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true

echo ">> Starting '$NAME' (CSI_SOURCE=$CSI_SOURCE) ..."
"$DOCKER" run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p "${PORT}:3000" \
  -p "${WS_PORT}:3001" \
  -p "5005:5005/udp" \
  "${RUN_ENV[@]}" \
  "$IMAGE"

sleep 4
echo ">> Status:"
"$DOCKER" ps --filter "name=${NAME}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# --- health probe (loopback host is always allowed) -------------------------
if command -v curl >/dev/null 2>&1; then
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://localhost:${PORT}/health" 2>/dev/null || true)"
  echo ">> Health: http://localhost:${PORT}/health -> ${CODE:-no-response}"
  [ "$CODE" = "200" ] || echo "   (not 200 yet — the server may still be starting; check: $DOCKER logs $NAME)"
fi

echo ""
echo ">> Open:  http://${IP:-<nas-ip>}:${PORT}"
if [ -n "$TOKEN" ]; then
  echo ">> API token (for /ws/sensing & /api/v1/*): $TOKEN"
  echo ">>   persisted at $TOKEN_FILE — re-runs reuse it automatically"
fi
echo ">> Logs:  $DOCKER logs -f $NAME"
echo ">> Stop:  $DOCKER rm -f $NAME"
if [ "$CSI_SOURCE" = "auto" ]; then
  echo "NOTE: CSI_SOURCE=auto exits (code 78) with no live CSI. Use simulated or esp32."
fi

exit 0
