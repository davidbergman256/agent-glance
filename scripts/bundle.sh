#!/bin/sh
# Builds "build/Agent Glance.app" from the SwiftPM products. With --install, copies it to ~/Applications.
: "${DEVELOPER_DIR:=/Library/Developer/CommandLineTools}"; export DEVELOPER_DIR  # pin the toolchain these scripts were written for
set -e
cd "$(dirname "$0")/.."
swift build -c release -q
BIN="$(swift build -c release --show-bin-path)"
APP="build/Agent Glance.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/AgentGlance" "$BIN/agent-glance-hook" "$APP/Contents/MacOS/"
codesign -s - --force --deep "$APP" 2>/dev/null
echo "built $APP"
if [ "$1" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    pkill -x AgentGlance 2>/dev/null || true
    rm -rf "$HOME/Applications/Agent Glance.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "installed $HOME/Applications/Agent Glance.app"
fi
