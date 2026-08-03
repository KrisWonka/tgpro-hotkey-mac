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

# ---- 让 TG Pro 真正接管风扇（关键，否则规则写了也不执行）----
# fanControlType=2       -> 用 Auto Max Rules（本项目下发规则的模式）；0 = 系统默认，完全不接管
# enableSystemOverrides  -> 每个风扇的系统覆写开关，(0,0) 时 Apple 固件说了算，风扇不会按规则转
#
# 必须先退出 TG Pro 再写：它在退出时会用内存里的旧值覆盖 plist，
# 运行中直接 defaults write 会被悄悄回滚（这个坑很难发现——规则明明写进去了，风扇就是不转）。
echo "→ 配置 TG Pro 接管风扇（fanControlType / enableSystemOverrides）"
TGPRO_DOMAIN="com.tunabellysoftware.tgpro"
if [ -d "/Applications/TG Pro.app" ]; then
  TGPRO_WAS_RUNNING=0
  if pgrep -x "TG Pro" >/dev/null 2>&1; then
    TGPRO_WAS_RUNNING=1
    osascript -e 'quit app "TG Pro"' >/dev/null 2>&1 || true
    sleep 3
    pkill -x "TG Pro" 2>/dev/null || true
    sleep 1
  fi

  OLD_FCT="$(defaults read "$TGPRO_DOMAIN" fanControlType 2>/dev/null || echo '<未设置>')"
  defaults write "$TGPRO_DOMAIN" fanControlType -int 2
  defaults delete "$TGPRO_DOMAIN" enableSystemOverrides 2>/dev/null || true
  defaults write "$TGPRO_DOMAIN" enableSystemOverrides -array -int 1 -int 1
  echo "   fanControlType: $OLD_FCT -> $(defaults read "$TGPRO_DOMAIN" fanControlType)"
  echo "   enableSystemOverrides -> (1, 1)"

  if [ "$TGPRO_WAS_RUNNING" = "1" ]; then
    open -ga "TG Pro"
    sleep 2
  fi
else
  echo "   (跳过：/Applications/TG Pro.app 不存在)"
fi

echo "→ 重载 Hammerspoon"
# 注意：对已在运行的 Hammerspoon 执行 open 只会激活窗口，**不会重新加载 init.lua**，
# 所以必须先退干净再开，否则装完看起来没反应。
osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
sleep 1
pkill -x Hammerspoon 2>/dev/null || true
sleep 1
open -ga Hammerspoon

echo ""
echo "→ 编译并安装 GUI"
bash app/build-app.sh

# ---- Hammerspoon 开机自启 ----
# 不设的话，重启后 Hammerspoon 不启动 = 菜单栏图标和快捷键全部消失，
# 很容易误判成「装失败了」。
echo "→ 设置 Hammerspoon 开机自启"
if osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "Hammerspoon"; then
  echo "   已在登录项里，跳过"
else
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Hammerspoon.app", hidden:true}' >/dev/null 2>&1 \
    && echo "   已加入登录项" \
    || echo "   ⚠ 自动添加失败，请手动在 Hammerspoon 设置里勾 Launch Hammerspoon at login"
fi

# ---- 可选：隐藏 Hammerspoon 自己的锤子图标，给菜单栏腾位置 ----
# 有刘海的 MacBook 上菜单栏很容易挤爆：装不下的图标会被塞到刘海底下，看起来就是「图标没出现」。
# 设 HIDE_HS_MENUICON=1 可隐藏锤子（约省 30px；之后要开 HS 控制台重新打开 Hammerspoon.app 即可）。
if [ "${HIDE_HS_MENUICON:-0}" = "1" ]; then
  echo "→ 隐藏 Hammerspoon 锤子图标（HIDE_HS_MENUICON=1）"
  if ! grep -q 'hs.menuIcon(false)' "$INIT_LUA" 2>/dev/null; then
    printf '\n-- 隐藏 Hammerspoon 自己的锤子图标，给菜单栏腾位置\nhs.menuIcon(false)\n' >> "$INIT_LUA"
  fi
fi

echo ""
echo "✅ 装好了。默认快捷键 ⌃⌥⌘8 在档位列表里循环（Auto / Performance / Turbo / Cooldown ...）"
echo "   点菜单栏那个字母（S/P/T）也能切档。Spotlight 搜「TG Hotkey」改设置 / 改曲线。"
echo ""
echo "⚠️  还需要你手动做一次（脚本代替不了）："
echo "   打开 TG Pro，授权 fan helper 安装（会弹窗要密码）——没有它风扇控制不生效"
echo ""
echo "   风扇接管开关（fanControlType / enableSystemOverrides）脚本已自动配好。"
echo "   如果风扇仍不转，先确认当前温度：曲线在低温档位本来就是 0%，"
echo "   例如 Turbo 曲线 ≤30°C 给 0%、35°C 才 10%、40°C 才 50%，闲置时不转是正常的。"
