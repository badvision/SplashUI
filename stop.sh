#!/bin/zsh
# SplashUI — full teardown: UI first (so it cannot react/auto-restart), then the service.
# Bring both back with ./start.sh
PORT="${SPLASH_PORT:-8123}"
SRV_PATTERN="server[.]server.*--port $PORT"

pkill -f 'MacOS/splash-ui' 2>/dev/null || true
pkill -f 'MacOS/splash-launcher' 2>/dev/null || true

pids=$(pgrep -f "$SRV_PATTERN" || true)
if [ -z "$pids" ]; then
  echo "stopped (UI only; service was not running)"
  exit 0
fi
kill $pids 2>/dev/null || true
for i in {1..10}; do
  [ -z "$(pgrep -f "$SRV_PATTERN" || true)" ] && break
  sleep 1
done
pids=$(pgrep -f "$SRV_PATTERN" || true)
[ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
echo "stopped (UI + service on :$PORT)"
