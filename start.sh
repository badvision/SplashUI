#!/bin/zsh
# SplashUI — full reset: (re)start the engine server, then (re)start the menu-bar UI,
# which adopts the running server. Idempotent: always ends with a fresh UI attached to
# a fresh server, so a stale UI can never linger. NOTE: kills in-flight requests on the
# old server — don't run mid-conversation.
#
#   SPLASH_VERSION  engine version        (default 1.3.0)
#   SPLASHUI_HOME   install root          (default ~/SplashUI)
#   SPLASH_PORT     engine port           (default 8123)
#   SPLASH_KEY      engine api-key        (default splash-standalone-1)
#   SPLASH_MODEL_ROOT  model directory    (default $SPLASHUI_HOME/models/..., falling
#                                         back to the LM Studio copy)
#   SPLASH_MAX_CACHE_DISK  SSD cache cap (default 100g)
#   SPLASH_ANE       GPU+Neural-Engine prefill split (default on; off = GPU-only)
set -eu
PKG="$(cd "$(dirname "$0")" && pwd)"

KIT_VERSION="${SPLASH_VERSION:-1.3.0}"
ROOT="${SPLASHUI_HOME:-$HOME/SplashUI}"
KIT="$ROOT/kit/splash-$KIT_VERSION-arm64-macos26"
PORT="${SPLASH_PORT:-8123}"
KEY="${SPLASH_KEY:-splash-standalone-1}"
MODEL_ROOT="${SPLASH_MODEL_ROOT:-$ROOT/models/incoai/Qwen3.8-27B-Splash}"
[ -d "$MODEL_ROOT" ] || MODEL_ROOT="$HOME/.lmstudio/models/incoai/Qwen3.8-27B-Splash"
[ -d "$KIT" ] || { echo "kit not found at $KIT — run ./install.sh first" >&2; exit 1; }
[ -d "$MODEL_ROOT" ] || { echo "model not found (tried $ROOT/models and ~/.lmstudio/models) — run ./install.sh" >&2; exit 1; }

export SPLASH_KIT_DIR="$KIT"
export SPLASH_MODEL_ROOT="$MODEL_ROOT"
export SPLASH_PORT="$PORT"
export SPLASH_KEY="$KEY"
export SPLASH_ANE="${SPLASH_ANE:-on}"
ANE_ARGS=()
if [ "$SPLASH_ANE" != "on" ]; then ANE_ARGS=(--disable-ane); fi

APP="$PKG/build/SplashUI.app"
UI_BIN="$APP/Contents/MacOS/splash-ui"

echo "stopping UI (current + legacy)..."
pkill -f 'MacOS/splash-ui' 2>/dev/null || true
pkill -f 'MacOS/splash-launcher' 2>/dev/null || true

echo "stopping service on 127.0.0.1:$PORT ..."
SRV_PATTERN="server[.]server.*--port $PORT"
pids=$(pgrep -f "$SRV_PATTERN" || true)
if [ -n "$pids" ]; then
  kill $pids 2>/dev/null || true
  for i in {1..15}; do
    [ -z "$(pgrep -f "$SRV_PATTERN" || true)" ] && break
    sleep 1
  done
  pids=$(pgrep -f "$SRV_PATTERN" || true)
  if [ -n "$pids" ]; then kill -9 $pids 2>/dev/null || true; fi
fi

STAMP=$(date +%Y%m%d-%H%M%S)
LOG="/tmp/splashui-$STAMP.log"
ln -sf "$LOG" /tmp/splashui.log

echo "starting service (model: $MODEL_ROOT, ANE: $SPLASH_ANE)..."
cd "$KIT"
nohup ./python/bin/python -u -m server.server "$MODEL_ROOT" \
  --tokenizer "$MODEL_ROOT/tokenizer" \
  --model incoai/Qwen3.8-27B-Splash \
  --binary ./engine/splash \
  --host 127.0.0.1 --port $PORT --api-key $KEY \
  --persistent-cache --max-cache-disk "${SPLASH_MAX_CACHE_DISK:-100g}" \
  --idle-release "${SPLASH_IDLE_RELEASE:-240m}" ${ANE_ARGS[@]+"${ANE_ARGS[@]}"} > "$LOG" 2>&1 &
SRV_PID=$!
echo "service pid $SRV_PID — log: $LOG (symlink /tmp/splashui.log)"

echo "waiting for ready..."
ready=0
for i in {1..180}; do
  if curl -s -m 2 -H "x-api-key: $KEY" "http://127.0.0.1:$PORT/status" 2>/dev/null \
    | /usr/bin/python3 -c 'import json,sys
try:
    sys.exit(0 if json.load(sys.stdin).get("ready") else 1)
except Exception:
    sys.exit(1)' 2>/dev/null; then
    ready=1
    echo "ready after ${i}s"
    break
  fi
  if ! kill -0 $SRV_PID 2>/dev/null; then
    echo "service died during startup — last log lines:" >&2
    tail -5 "$LOG" >&2 || true
    exit 1
  fi
  sleep 1
done
[ $ready -eq 1 ] || echo "warn: not ready after 180 s — UI will show LOADING/DOWN" >&2

[ -x "$UI_BIN" ] || { echo "UI not built — run: ./build.sh" >&2; exit 1; }
echo "starting UI..."
nohup "$UI_BIN" > /dev/null 2>&1 &
echo "done: service pid $SRV_PID + SplashUI menu-bar app (adopted)"
