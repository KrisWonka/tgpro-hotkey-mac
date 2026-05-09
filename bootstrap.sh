#!/usr/bin/env bash
# 一键引导：在全新 macOS 上装好 tgpro-hotkey-mac
# 包含所有前置依赖（Xcode CLT / Homebrew / Hammerspoon / TG Pro）
#
# 用法（在新 Mac 上）：
#   curl -fsSL https://raw.githubusercontent.com/KrisWonka/tgpro-hotkey-mac/main/bootstrap.sh | bash

set -euo pipefail

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }

[[ "$(uname)" == "Darwin" ]] || { red "仅支持 macOS"; exit 1; }

WORKDIR="${WORKDIR:-$HOME}"
mkdir -p "$WORKDIR"

# ---- 1. Xcode Command Line Tools ----
if ! xcode-select -p >/dev/null 2>&1; then
  bold "[1/5] 安装 Xcode Command Line Tools（弹窗里点 Install，等装完即可继续）…"
  xcode-select --install || true
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
  green "  -> CLT 就绪"
else
  green "[1/5] Xcode CLT 已装，跳过"
fi

# ---- 2. Homebrew ----
if ! command -v brew >/dev/null 2>&1; then
  bold "[2/5] 安装 Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ];   then eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  green "[2/5] Homebrew 已装，跳过"
  eval "$(brew shellenv)"
fi

# ---- 3. Hammerspoon + TG Pro ----
bold "[3/5] 安装 Hammerspoon / TG Pro…"
brew install --cask hammerspoon tg-pro

# ---- 4. 启动一次 Hammerspoon 申请 Accessibility 权限 ----
if ! pgrep -q Hammerspoon; then
  bold "[4/5] 首次启动 Hammerspoon — 弹窗里给「辅助功能 / Accessibility」权限…"
  open -ga Hammerspoon
  sleep 2
else
  green "[4/5] Hammerspoon 已在运行"
fi

# ---- 5. 拉取 + 跑 install.sh ----
bold "[5/5] 拉取 tgpro-hotkey-mac 到 $WORKDIR 并安装…"
cd "$WORKDIR"
if [ -d "tgpro-hotkey-mac/.git" ]; then
  (cd tgpro-hotkey-mac && git pull --ff-only) || true
  green "  -> 仓库已在，已尝试更新"
else
  git clone https://github.com/KrisWonka/tgpro-hotkey-mac.git
fi
( cd "$WORKDIR/tgpro-hotkey-mac" && ./install.sh )

green ""
green "🎉 tgpro-hotkey-mac 装好了"
cat <<EOF

下一步:
  - System Settings → Privacy & Security → Accessibility
    确认 Hammerspoon 是 ON（否则快捷键不响应）
  - 打开 TG Pro 一次（dock / Spotlight），授权它要的权限（fan helper 装要密码）
  - **重要**：进 TG Pro Settings → Fan，确认「Use Manual instead of Max」**没勾**
  - ⌃⌥⌘ + 8 在档位列表里循环（Auto / Performance / Turbo / Cooldown ...）
  - Spotlight 搜「TG Hotkey」开 GUI 拖曲线
EOF
