#!/bin/zsh
# Build SplashUI.app (no Xcode; CLT swiftc only). Ad-hoc signed, menu-bar only.
set -eu
cd "$(dirname "$0")"
rm -rf build
mkdir -p build/SplashUI.app/Contents/MacOS build/SplashUI.app/Contents/Resources
cp Info.plist build/SplashUI.app/Contents/Info.plist
cp Resources/panel.html build/SplashUI.app/Contents/Resources/
swiftc -O Sources/main.swift -o build/SplashUI.app/Contents/MacOS/splash-ui \
  -framework Cocoa -framework WebKit
codesign --force -s - build/SplashUI.app
echo "built build/SplashUI.app"
