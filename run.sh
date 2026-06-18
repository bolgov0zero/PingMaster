#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build 2>&1

APP=/tmp/PingMaster.app
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/debug/PingMaster "$APP/Contents/MacOS/PingMaster"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

pkill PingMaster 2>/dev/null || true
sleep 0.5

open "$APP"
echo "Launched PingMaster — look for the dot icon in your menu bar"
