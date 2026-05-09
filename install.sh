#!/usr/bin/env bash
# tgpro-hotkey-mac installer
# 把 lua + Swift helpers 装到 ~/.hammerspoon，编译并安装 TG Hotkey.app GUI
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"

mkdir -p "$HS_DIR"

# ---- 依赖：TG Pro（核心，没它项目无意义）----
if [ ! -d "/Applications/TG Pro.app" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "→ 未检测到 TG Pro，用 brew 自动安装…"
    brew install --cask tg-pro
  else
    echo "✗ 未检测到 TG Pro，也没有 brew。" >&2
    echo "  请先装 Homebrew，再 brew install --cask tg-pro，" >&2
    echo "  或手动从 https://www.tunabellysoftware.com/tgpro/ 下载。" >&2
    exit 1
  fi
fi

# ---- 依赖：Hammerspoon ----
if [ ! -d "/Applications/Hammerspoon.app" ]; then
  echo "✗ 未检测到 Hammerspoon。请先 brew install --cask hammerspoon。" >&2
  exit 1
fi

# ---- 依赖：swiftc ----
if ! command -v swiftc >/dev/null 2>&1; then
  echo "✗ 未检测到 swiftc。请装 Xcode Command Line Tools：xcode-select --install" >&2
  exit 1
fi

echo "→ 复制 tgpro-hotkey.lua"
cp tgpro-hotkey.lua "$HS_DIR/tgpro-hotkey.lua"

echo "→ 编译 readtemp（Apple Silicon CPU 温度读取，Cooldown 档位用）"
swiftc readtemp.swift -framework IOKit -O -o "$HS_DIR/readtemp"

echo "→ 编译 tgpro-rules（写规则到 TG Pro plist + 重启 TG Pro）"
swiftc tgpro-rules.swift -O -o "$HS_DIR/tgpro-rules"

# 在 init.lua 里加 require（如果还没加）
if [ -f "$INIT_LUA" ] && grep -q 'require("tgpro-hotkey")' "$INIT_LUA"; then
  echo "→ init.lua 里已经有 require(\"tgpro-hotkey\")，跳过"
else
  echo "→ 在 $INIT_LUA 末尾追加 require(\"tgpro-hotkey\")"
  {
    echo ""
    echo "-- tgpro-hotkey-mac (https://github.com/KrisWonka/tgpro-hotkey-mac)"
    echo 'require("tgpro-hotkey")'
  } >> "$INIT_LUA"
fi

echo "→ 重载 Hammerspoon"
osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
sleep 1
open -ga Hammerspoon

echo ""
echo "→ 编译并安装 GUI"
bash app/build-app.sh

echo ""
echo "✅ 装好了。默认快捷键 ⌃⌥⌘8 在档位列表里循环（Auto / Performance / Turbo / Cooldown ...）"
echo "   Spotlight 搜「TG Hotkey」改设置 / 改曲线。"
echo ""
echo "⚠️  TG Pro 一次性设置（重要）："
echo "   1. 打开 TG Pro，授权 fan helper 安装（要输一次密码）"
echo "   2. 进 Settings → Fan，确认「Use Manual instead of Max」**没勾**"
echo "      勾上的话 TG Pro 会忽略 Auto Max Rules，本项目就管不了风扇"
