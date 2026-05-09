#!/usr/bin/env bash
# tgpro-hotkey-mac uninstaller
set -euo pipefail

HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"
MARKER='-- tgpro-hotkey-mac (https://github.com/KrisWonka/tgpro-hotkey-mac)'
APP_DIR="/Applications/TG Hotkey.app"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }

read -p "确定卸载 tgpro-hotkey-mac？(y/N) " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "取消"; exit 0; }

# 1. ~/.hammerspoon 资产
bold "清理 $HS_DIR/…"
for f in tgpro-hotkey.lua tgpro-hotkey-config.json readtemp tgpro-rules; do
  if [ -e "$HS_DIR/$f" ]; then
    rm -f "$HS_DIR/$f"
    green "  rm $f"
  fi
done

# 2. 从 init.lua 去掉 require
if [ -f "$INIT_LUA" ] && grep -qF "$MARKER" "$INIT_LUA"; then
  bold "从 init.lua 去掉 require…"
  TMP="$(mktemp)"
  awk -v marker="$MARKER" '
    BEGIN { skip = 0 }
    {
      if ($0 == marker) { skip = 2; if (prev == "") prev_skipped = 1; next }
      if (skip > 0) { skip--; next }
      if (prev_skipped) { prev_skipped = 0; if ($0 == "") next }
      print prev
      prev = $0
    }
    END { if (!prev_skipped) print prev }
  ' "$INIT_LUA" | sed '1{/^$/d;}' > "$TMP"
  mv "$TMP" "$INIT_LUA"
  green "  done"
fi

# 3. /Applications/TG Hotkey.app
if [ -d "$APP_DIR" ]; then
  bold "删 $APP_DIR…"
  rm -rf "$APP_DIR"
  green "  done"
fi

# 4. 重载 Hammerspoon
bold "重载 Hammerspoon…"
osascript -e 'quit app "Hammerspoon"' 2>/dev/null || true
sleep 1
open -a Hammerspoon 2>/dev/null || true

green "卸载完成。注意：TG Pro 本身没动，要的话手动 brew uninstall --cask tg-pro。"
