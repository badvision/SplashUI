#!/bin/zsh
# Run the pure-logic regression tests (no AppKit, no Xcode, no SPM needed).
# The test entry point is Tests/main.swift (a top-level-code file, hence the name).
set -eu
cd "$(dirname "$0")"
swiftc -O Sources/ui_logic.swift Tests/main.swift -o /tmp/splashui-logic-test
/tmp/splashui-logic-test
rm -f /tmp/splashui-logic-test

# Optional, offline UI stage: install its scoped dependency once with npm ci.
if command -v node >/dev/null 2>&1; then
  if [ -d Tests/ui/node_modules/jsdom ]; then
    node Tests/ui/panel.test.mjs
  else
    echo "SKIP panel UI tests: run npm ci --prefix Tests/ui to install jsdom"
  fi
else
  echo "SKIP panel UI tests: node is not installed"
fi
