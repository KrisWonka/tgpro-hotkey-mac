# tgpro-hotkey-mac

[English](README.md) | [中文](README.zh.md)

> ⚠️ **本项目是 [TG Pro](https://www.tunabellysoftware.com/tgpro/) 的配套工具**，TG Pro 必须先装好（试用版也行），否则无法工作。我们不直接操作 SMC，而是驱动 TG Pro 的规则引擎。

macOS 全局快捷键，按用户自定义的「档位列表」循环切换 **TG Pro** 的风扇控制 —— **支持真·多段温度曲线**（在折线图上拖点编辑），预置 Silence / Performance / Turbo 三档 + 自定义。补足 TG Pro 自身缺的能力：**用一个快捷键在多个命名「风扇档位」之间切换**。

| | |
|---|---|
| **为什么需要** | TG Pro 有 SMC 写控制权（Apple Silicon 上唯一拥有合法 Apple Developer 签名 SMC helper 的第三方工具），但只能存一组 Auto Max Rules。本项目补的就是这一层：命名档位 + 快捷键循环 + 温度自动 cooldown |
| **它做什么** | 每按一次 `⌃⌥⌘+8` 在档位列表里前进一档。每档把对应规则写入 TG Pro 的 `autoConfigsPowerAdapter` plist 然后重启 TG Pro（约 0.3 秒，几乎无感），TG Pro 接管后持续按规则调速 |
| **它不做什么** | 直接操控 SMC、绕开 TG Pro 自己控速、替换 TG Pro 主程序 UI |

## 功能

- **可配置档位列表** — 增删、↑↓ 排序；每档可以是：
  - **Auto** — 清空 TG Pro 的规则，回到系统默认温控
  - **Full Blast** — 单条规则「>0°C 全速」（可设 N 分钟自动回 Auto）
  - **Cooldown** — 全速直到平均 CPU 温度降到目标值（默认 40°C）后自动回 Auto
  - **Temperature** — 多点风扇曲线。预置 Silence / Performance / Turbo，或空白 Custom
- **拖拽编辑曲线**：SwiftUI 折线图，5°C / 5% 网格，拖点调整，右键删除
- **全局快捷键**（默认 `⌃⌥⌘+8`）按一次前进一档
- **每档可展开调参** — 改名、改曲线点、调 Cooldown 阈值等
- **Apple Silicon 温度读取**：自带 Swift 工具 `readtemp`（基于 `IOHIDEventSystemClient`）
- **SwiftUI 配置 GUI**：TG Hotkey.app

> Apple Silicon (Mac17,9) 验证通过。需要 TG Pro 2.103+。

## 工作原理

每个档位被渲染成 TG Pro 的 Auto Max Rules JSON 列表。按快捷键时，Swift 助手 `tgpro-rules`：

1. 退出 TG Pro 并等它完全死透（否则 TG Pro 退出 handler 会用内存里的旧状态覆盖我们的 plist）
2. 把规则编码成 TG Pro 的 `NSKeyedArchive` plist 格式（`AutoBoostConfigModel` 数组）
3. 写到 `~/Library/Preferences/com.tunabellysoftware.tgpro.plist` 的 `autoConfigsPowerAdapter` + `autoConfigsBattery`
4. 把 `useManualInsteadOfMax` 设为 `false`（这玩意为 true 时 TG Pro 忽略 Auto Max Rules，只听手动滑块）
5. 后台重新打开 TG Pro，它读规则后开始持续按曲线调速

Cooldown 档额外用 `readtemp` 监控 CPU 温度，降到阈值后清空规则。

| 组件 | 作用 |
|------|------|
| `tgpro-hotkey.lua` | Hammerspoon 主逻辑：快捷键、档位状态机、Cooldown 轮询 |
| `readtemp` (Swift) | 读 Apple Silicon CPU 温度（IOHIDEventSystemClient） |
| `tgpro-rules` (Swift) | JSON 规则编码成 TG Pro NSKeyedArchive plist + 重启 TG Pro |
| `TG Hotkey.app` (SwiftUI) | 配置 GUI：档位列表 + 拖拽曲线编辑器 |
| `~/.hammerspoon/tgpro-hotkey-config.json` | 单一配置源，App 写入，lua 读取 |

## 安装

### 全新 Mac 一键装

把所有依赖（Xcode CLT、Homebrew、Hammerspoon、**TG Pro**）+ 本项目一次性装好：

```bash
curl -fsSL https://raw.githubusercontent.com/KrisWonka/tgpro-hotkey-mac/main/bootstrap.sh | bash
```

### 手动

依赖：
- [TG Pro](https://www.tunabellysoftware.com/tgpro/)（`brew install --cask tg-pro`）—— 14 天免费试用，之后约 $30 一次性
- [Hammerspoon](https://www.hammerspoon.org/)（`brew install --cask hammerspoon`）
- Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/KrisWonka/tgpro-hotkey-mac.git
cd tgpro-hotkey-mac
./install.sh
```

安装脚本编译 `readtemp` + `tgpro-rules` 到 `~/.hammerspoon/`，拷 lua、在 init.lua 追加 `require("tgpro-hotkey")`、编 `TG Hotkey.app`、重载 Hammerspoon。

### TG Pro 一次性设置 ⚠️

装完后打开 TG Pro 一次：
1. 给它要求的权限（辅助功能、fan helper 安装要输一次密码）
2. **进 Settings → Fan，确认「Use Manual instead of Max」没勾。** 勾上的话 TG Pro 会忽略 Auto Max Rules，本项目就管不了风扇。

## 使用

### 快捷键
默认 **`⌃⌥⌘ + 8`** 在档位列表里前进一档（GUI 里可改）。默认列表：Auto → Performance → Turbo → Cooldown → Auto。

### 配置 GUI（**TG Hotkey.app**）
Spotlight 搜「TG Hotkey」打开。三个标签：

- **Settings**：
  - **循环档位**：增删（Auto / Full Blast / Cooldown / Temperature）、↑↓ 排序；点 ▶ 展开调参
  - **Temperature** 档：拖折线图上的点（5°C / 5% 自动吸附），或载入 Silence / Performance / Turbo 预设
  - **快捷键**：组合键、启用开关
  - **提示**：屏幕中央提示开关、Cooldown 完成文字、显示时长
- **Status**：实时显示 TG Pro / Hammerspoon / 当前状态
- **About**：仓库链接

保存后自动重载 Hammerspoon。

## 手动改配置

编辑 `~/.hammerspoon/tgpro-hotkey-config.json` 后 reload Hammerspoon。Schema：

```json
{
  "hotkeyEnabled": true,
  "hotkeyMods": ["ctrl", "alt", "cmd"],
  "hotkeyKey": "8",
  "alertEnabled": true,
  "alertDuration": 1.2,
  "alertCooldownDone": "Cooldown done ✓",
  "cycleSteps": [
    { "type": "auto", "name": "" },
    { "type": "temperature", "name": "Performance",
      "configSensor": 4, "configFan": 0,
      "curve": [
        { "temperatureLimit": 30, "percent": 0 },
        { "temperatureLimit": 40, "percent": 30 },
        { "temperatureLimit": 50, "percent": 45 },
        { "temperatureLimit": 60, "percent": 60 },
        { "temperatureLimit": 70, "percent": 75 },
        { "temperatureLimit": 80, "percent": 90 },
        { "temperatureLimit": 90, "percent": 100 }
      ]
    },
    { "type": "fullBlast", "autoRevertEnabled": false, "autoRevertSec": 600 },
    { "type": "cooldown", "cooldownTargetTemp": 40, "cooldownPollSec": 3 }
  ]
}
```

`cycleSteps[].type` 是 `auto` / `fullBlast` / `cooldown` / `temperature` 之一。`configSensor` 4 = "Highest CPU"；`configFan` 0 = "All Fans"（TG Pro 内部索引）。

## 卸载

```bash
./uninstall.sh
```

TG Pro 不动，要一起删请 `brew uninstall --cask tg-pro`。

## 致谢

- [TG Pro](https://www.tunabellysoftware.com/tgpro/)（Tunabelly Software 出品）—— 真正干 SMC 风扇控制的活，我们只是组织它的规则
- [Hammerspoon](https://www.hammerspoon.org/) —— macOS 自动化框架，撑起快捷键 + 状态机
- `IOHIDEventSystemClient` 温度读取的思路参考 [Stats](https://github.com/exelban/stats) 和 TG Pro 自身

## License

MIT
