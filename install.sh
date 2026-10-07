#!/bin/bash
# SplashUI one-time install: pinned Splash engine release + the Qwen3.8-27B model.
#
#   SPLASH_VERSION  engine version to pin      (default 1.3.0)
#   SPLASHUI_HOME   install root               (default ~/SplashUI)
#   HF_TOKEN        set only if the model needs auth
#
# Idempotent: safe to re-run; skips what is already present.
set -euo pipefail
KIT_VERSION="${SPLASH_VERSION:-1.3.0}"
ROOT="${SPLASHUI_HOME:-$HOME/SplashUI}"
KIT_NAME="splash-$KIT_VERSION-arm64-macos26"
KIT_DIR="$ROOT/kit"
MODELS="$ROOT/models"
MODEL_ID="incoai/Qwen3.8-27B-Splash"
REL="https://github.com/incoai/splash/releases/download/$KIT_VERSION"

# --- engine (pinned release, sha256-verified) ---
if [ -x "$KIT_DIR/$KIT_NAME/engine/splash" ]; then
  echo "engine $KIT_VERSION already installed: $KIT_DIR/$KIT_NAME"
else
  echo "downloading engine $KIT_NAME (~70 MB)..."
  curl -fsSL -o "/tmp/$KIT_NAME.tar.gz" "$REL/$KIT_NAME.tar.gz"
  curl -fsSL -o "/tmp/$KIT_NAME.tar.gz.sha256" "$REL/$KIT_NAME.tar.gz.sha256"
  expected=$(tr -d '[:space:]' < "/tmp/$KIT_NAME.tar.gz.sha256")
  actual=$(shasum -a 256 "/tmp/$KIT_NAME.tar.gz" | cut -d' ' -f1)
  if [ "$expected" != "$actual" ]; then
    echo "ERROR: sha256 mismatch ($actual != $expected) — aborting" >&2
    exit 1
  fi
  mkdir -p "$KIT_DIR"
  tar xzf "/tmp/$KIT_NAME.tar.gz" -C "$KIT_DIR"
  rm -f "/tmp/$KIT_NAME.tar.gz" "/tmp/$KIT_NAME.tar.gz.sha256"
  echo "engine installed + verified: $KIT_DIR/$KIT_NAME"
fi

# --- model (16 GB): reuse what exists, else download from Hugging Face ---
mkdir -p "$MODELS"
TARGET="$MODELS/$MODEL_ID"
if [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
  echo "model already present: $TARGET"
elif [ -d "$HOME/.lmstudio/models/$MODEL_ID" ] && [ -n "$(ls -A "$HOME/.lmstudio/models/$MODEL_ID" 2>/dev/null)" ]; then
  mkdir -p "$(dirname "$TARGET")"
  ln -s "$HOME/.lmstudio/models/$MODEL_ID" "$TARGET"
  echo "linked existing LM Studio copy: $TARGET"
else
  echo "downloading $MODEL_ID (~16 GB) — this takes a while..."
  /usr/bin/python3 -c "import huggingface_hub" 2>/dev/null \
    || /usr/bin/python3 -m pip install --user -q huggingface_hub
  /usr/bin/python3 - "$MODEL_ID" "$TARGET" <<'PY'
import os, sys
from huggingface_hub import snapshot_download
model_id, local_dir = sys.argv[1], sys.argv[2]
snapshot_download(model_id, local_dir=local_dir)
PY
fi

cat <<EOF

Install complete:
  engine:  $KIT_DIR/$KIT_NAME
  model:   $TARGET

Next:
  ./build.sh     # builds build/SplashUI.app (needs Command Line Tools)
  ./start.sh     # starts the engine server + menu-bar UI
EOF
