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

装完后打开 TG Pro 一次，**给它要求的权限**——fan helper 安装要输一次密码。这步脚本代替不了，没有这个 helper 风扇控制完全不生效。

其余的风扇接管开关（`fanControlType` / `enableSystemOverrides`）`install.sh` 已经自动配好，不用手点。如果你想确认：

```bash
defaults read com.tunabellysoftware.tgpro fanControlType          # 要是 2
defaults read com.tunabellysoftware.tgpro enableSystemOverrides   # 要是 (1, 1)
```

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
    { "type": "auto", "name": "Silence" },
    { "type": "temperature", "name": "Performance",
      "configSensor": 0, "configFan": 0,
      "curve": [
        { "temperatureLimit": 30, "percent": 0 },
        { "temperatureLimit": 35, "percent": 10 },
        { "temperatureLimit": 45, "percent": 25 },
        { "temperatureLimit": 50, "percent": 55 },
        { "temperatureLimit": 60, "percent": 75 },
        { "temperatureLimit": 70, "percent": 80 },
        { "temperatureLimit": 80, "percent": 90 },
        { "temperatureLimit": 90, "percent": 100 }
      ]
    },
    { "type": "temperature", "name": "Turbo",
      "configSensor": 0, "configFan": 0,
      "curve": [
        { "temperatureLimit": 20, "percent": 0 },
        { "temperatureLimit": 30, "percent": 0 },
        { "temperatureLimit": 35, "percent": 10 },
        { "temperatureLimit": 40, "percent": 50 },
        { "temperatureLimit": 50, "percent": 75 },
        { "temperatureLimit": 60, "percent": 95 },
        { "temperatureLimit": 70, "percent": 100 },
        { "temperatureLimit": 80, "percent": 100 },
        { "temperatureLimit": 90, "percent": 100 }
      ]
    }
  ]
}
```

`cycleSteps[].type` 是 `auto` / `fullBlast` / `cooldown` / `temperature` 之一。`configSensor` 0 = "Any Sensor"（跨 Mac 通用）；`configFan` 0 = "All Fans"（TG Pro 内部索引）。

## 常见问题 / 踩过的坑

### 切到 Turbo 了，风扇还是不转

按可能性从高到低排查：

1. **温度还没到触发点——多数情况是这个，不是故障。** 曲线是「温度 ≥ 某档 → 该档百分比」，Turbo 默认 ≤30°C 给 0%、35°C 给 10%、40°C 才 50%。机器闲着三十几度时风扇不转是**正确行为**。想验证就跑个负载：

   ```bash
   for i in 1 2 3 4; do (yes > /dev/null &); done   # 加负载
   ~/.hammerspoon/readtemp                          # 看温度爬上去
   pkill yes                                        # 停掉
   ```

2. **TG Pro 没在接管风扇。** 这是最隐蔽的一个：规则明明写进去了（`tgpro-rules apply` 也回显成功），但 TG Pro 处在系统默认模式，压根不执行。

   ```bash
   defaults read com.tunabellysoftware.tgpro fanControlType         # 0 = 系统默认（不接管），要 2
   defaults read com.tunabellysoftware.tgpro enableSystemOverrides  # (0, 0) = 不覆写，要 (1, 1)
   ```

   新版 `install.sh` 会自动配这两个键。手动改的话**必须先退出 TG Pro**——它退出时会用内存里的旧值覆盖 plist，运行中直接 `defaults write` 会被悄悄回滚：

   ```bash
   osascript -e 'quit app "TG Pro"'; sleep 3
   defaults write com.tunabellysoftware.tgpro fanControlType -int 2
   defaults write com.tunabellysoftware.tgpro enableSystemOverrides -array -int 1 -int 1
   open -ga "TG Pro"
   ```

3. **fan helper 没装/没授权。** 检查 daemon 在不在：

   ```bash
   sudo launchctl print system/com.tunabellysoftware.TGFanHelper | grep 'state ='   # 要 running
   ```

### 菜单栏没有那个档位字母（S / P / T）

1. **菜单栏挤爆了，图标被刘海吞了。** 有刘海的 MacBook 上，状态栏图标是从右往左排的，排不下的会落到刘海底下——**不是没生成，是看不见**。用 `hs.menuIcon(false)` 隐藏 Hammerspoon 自己的锤子能腾出约 30px（安装时 `HIDE_HS_MENUICON=1 ./install.sh` 会自动加），再不够就精简别的图标（比如 TG Pro 自己的第二温度、风扇转速显示）。

   注意：Hammerspoon 报的 `frame` 坐标**不反映刘海遮挡**，被盖住的图标照样有正常坐标，所以不能靠坐标判断可见性。

2. **Hammerspoon 没开机自启。** 重启后 HS 没启动 = 图标和快捷键全没。新版 `install.sh` 会自动加登录项；也可在 Hammerspoon 设置里勾 Launch Hammerspoon at login。

3. **改完配置没真正重载。** 对已在运行的 Hammerspoon 执行 `open` 只是激活窗口，**不会重新加载 init.lua**。要退干净再开：

   ```bash
   osascript -e 'quit app "Hammerspoon"'; sleep 1; pkill -x Hammerspoon; open -ga Hammerspoon
   ```

### 快捷键好使，但点菜单栏图标没反应

v1.0 的 bug，已修。原因是点击回调里引用的 `cycle` 声明在它后面（`local function cycle`），闭包捕获到的是全局 `cycle`（`nil`），点击时报 `attempt to call a nil value`；热键因为绑定在定义之后所以不受影响。升级到最新版即可。

### 图标出现了一会儿又消失

`hs.menubar` / `hs.timer` 对象存在 `local` 变量里，chunk 执行完就没有强引用，会被 Lua GC 回收。本项目已改成全局变量（`statusBar`）。自己写 Hammerspoon 模块时也要注意这点。

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
