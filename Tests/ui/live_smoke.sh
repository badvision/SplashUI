#!/bin/sh
# DOM assertions drive the real WKWebView; the screenshot is evidence only.
set -eu
exec node "$(dirname "$0")/live_smoke.mjs" "$@"
