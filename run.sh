#!/usr/bin/env bash
#
# Builds (if needed) and launches TokenUsage.
#
set -euo pipefail
cd "$(dirname "$0")"

APP="TokenUsage"
BUNDLE="$APP.app"

./build.sh "${1:-release}"

# Relaunch: kill any running copy first so we always run the fresh build.
pkill -x "$APP" 2>/dev/null || true
sleep 0.3
open "$BUNDLE"
echo "✓ Launched $BUNDLE (look for the gauge icon in the menu bar)"
