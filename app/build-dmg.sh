#!/usr/bin/env bash
# 把已经在 /Applications 的 TG Hotkey.app 打成 DMG（用于 GitHub Release）
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="TG Hotkey"
APP_PATH="/Applications/${APP_NAME}.app"
VERSION="${1:-1.0.0}"
OUT_DIR="../dist"
DMG_PATH="${OUT_DIR}/FanHotkey-${VERSION}.dmg"
STAGING="$(mktemp -d)/dmg"

[ -d "$APP_PATH" ] || { echo "✗ $APP_PATH 不存在，先跑 build-app.sh"; exit 1; }

mkdir -p "$STAGING" "$OUT_DIR"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
echo "→ hdiutil create $DMG_PATH"
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$(dirname "$STAGING")"
echo "✅ $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"
