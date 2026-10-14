#!/bin/zsh
# Run the pure-logic regression tests (no AppKit, no Xcode, no SPM needed).
# The test entry point is Tests/main.swift (a top-level-code file, hence the name).
set -eu
cd "$(dirname "$0")"
swiftc -O Sources/ui_logic.swift Tests/main.swift -o /tmp/splashui-logic-test
/tmp/splashui-logic-test
rm -f /tmp/splashui-logic-test
