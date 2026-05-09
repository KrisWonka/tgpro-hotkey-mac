# tgpro-hotkey-mac

[English](README.md) | [中文](README.zh.md)

> ⚠️ **This is a companion utility for [TG Pro](https://www.tunabellysoftware.com/tgpro/).** TG Pro must be installed and licensed (or in trial) — this tool cannot work without it. We don't talk to SMC ourselves; we drive TG Pro's rule engine.

A macOS global hotkey that cycles **TG Pro**'s fan control through a user-defined list of modes — including real multi-segment temperature curves you edit by dragging points on a chart (Silence / Performance / Turbo / Custom). Fills the gap that TG Pro doesn't solve natively: **switch between named "fan profiles" with one keystroke**.

| | |
|---|---|
| **Why** | TG Pro has the SMC plumbing (the only third-party app on Apple Silicon with a properly Apple-Developer-signed SMC helper) but only one set of Auto Max Rules at a time. This adds the missing layer: named profiles + hotkey cycling + temp-driven cooldown |
| **What it does** | Each press of `⌃⌥⌘+8` advances one step in your cycle list. Each step rewrites TG Pro's `autoConfigsPowerAdapter` plist with that step's rules and bounces TG Pro (~0.3s, near-imperceptible). TG Pro then enforces those rules continuously |
| **What it does NOT do** | Talk to SMC directly. Modify your fans without TG Pro. Replace TG Pro's UI |

## Features

- **Configurable cycle list** — add / remove / reorder steps. Each step is one of:
  - **Auto** — clears TG Pro's rules, falls back to system temp control
  - **Full Blast** — single rule "100% when temp > 0°C" (with optional N-minute auto-revert)
  - **Cooldown** — full blast until average CPU temp drops below a threshold (default 40°C), then auto back to Auto
  - **Temperature** — a multi-point fan curve. Pre-built templates: Silence / Performance / Turbo, plus blank Custom
- **Drag-to-edit curve** in the SwiftUI configurator — chart with 5°C / 5% grid, drag points to adjust, right-click to delete
- **Global hotkey** (default `⌃⌥⌘+8`) advances the cycle one step
- **Per-step expandable params** — rename, edit curve points, tune cooldown threshold, etc.
- **Apple Silicon temperature reading** via a tiny Swift helper (`readtemp`) using `IOHIDEventSystemClient`
- SwiftUI configurator app (`TG Hotkey.app`) — Settings / Status / About tabs

> Verified on Apple Silicon (Mac17,9). Requires TG Pro 2.103+.

## How it works

Each cycle step is rendered into a JSON list of TG Pro Auto Max Rules. On hotkey press, the `tgpro-rules` Swift helper:

1. Quits TG Pro and waits for it to fully exit (otherwise TG Pro's quit handler overwrites our plist with its in-memory state)
2. Encodes the rules into TG Pro's `NSKeyedArchive` plist format (`AutoBoostConfigModel` array)
3. Writes the encoded data to `~/Library/Preferences/com.tunabellysoftware.tgpro.plist` for both `autoConfigsPowerAdapter` and `autoConfigsBattery`
4. Sets `useManualInsteadOfMax = false` so the rules actually take effect (when this is true, TG Pro ignores rules and only obeys the manual slider)
5. Reopens TG Pro in the background — it loads our rules and starts polling temperature

Cooldown steps additionally use `readtemp` to monitor CPU temp and auto-clear the rules once temp drops below the target.

| Component | Role |
|------|------|
| `tgpro-hotkey.lua` | Hammerspoon module — hotkey, cycle-list state machine, cooldown polling |
| `readtemp` (Swift) | Reads Apple Silicon CPU temperature via `IOHIDEventSystemClient` |
| `tgpro-rules` (Swift) | Encodes JSON rules to TG Pro's NSKeyedArchive plist + restarts TG Pro |
| `TG Hotkey.app` (SwiftUI) | Configurator GUI — cycle-list editor + drag-to-edit curve chart |
| `~/.hammerspoon/tgpro-hotkey-config.json` | Single source of truth — written by the app, read by the lua |

## Install

### Fresh-Mac one-liner

Bootstraps everything from scratch — Xcode CLT, Homebrew, Hammerspoon, **TG Pro**, then clones and installs:

```bash
curl -fsSL https://raw.githubusercontent.com/KrisWonka/tgpro-hotkey-mac/main/bootstrap.sh | bash
```

### Manual

Requires:
- [TG Pro](https://www.tunabellysoftware.com/tgpro/) (`brew install --cask tg-pro`) — 14-day free trial, then ~$30 one-time
- [Hammerspoon](https://www.hammerspoon.org/) (`brew install --cask hammerspoon`)
- Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/KrisWonka/tgpro-hotkey-mac.git
cd tgpro-hotkey-mac
./install.sh
```

The installer compiles `readtemp` + `tgpro-rules` into `~/.hammerspoon/`, copies the lua, appends `require("tgpro-hotkey")` to `init.lua`, builds `TG Hotkey.app`, and reloads Hammerspoon.

### One-time TG Pro setup ⚠️

After installing, open TG Pro once and:
1. Grant the permissions it asks for (Accessibility, fan helper install — needs your password once)
2. **Open Settings → Fan and confirm "Use Manual instead of Max" is NOT checked.** When that toggle is on, TG Pro ignores Auto Max Rules and our project can't drive fans.

## Usage

### Hotkey
Default **`⌃⌥⌘ + 8`** advances one step in your cycle list (rebindable in the GUI). Default cycle: Auto → Performance → Turbo → Cooldown → Auto.

### Configurator (`TG Hotkey.app`)
Spotlight search for "TG Hotkey". Three tabs:

- **Settings**:
  - **Cycle list** — add (Auto / Full Blast / Cooldown / Temperature), delete, reorder with ↑↓; click ▶ to expand and tune
  - **Temperature** steps: drag points on the curve chart (5°C / 5% snap), or load a Silence / Performance / Turbo template
  - **Hotkey** — global hotkey + enable toggle
  - **Alerts** — on-screen prompt, cooldown-done text, display duration
- **Status** — TG Pro install / Hammerspoon process / current state
- **About** — repo link

Hit "Save & Reload" to persist and bounce Hammerspoon.

## Manual config

Edit `~/.hammerspoon/tgpro-hotkey-config.json` directly without the GUI, then reload Hammerspoon. Schema:

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

`cycleSteps[].type` is `auto` / `fullBlast` / `cooldown` / `temperature`. `configSensor` 4 = "Highest CPU"; `configFan` 0 = "All Fans" (TG Pro's internal indices).

## Uninstall

```bash
./uninstall.sh
```

TG Pro itself is left alone — `brew uninstall --cask tg-pro` if you want to remove it too.

## Acknowledgements

- [TG Pro](https://www.tunabellysoftware.com/tgpro/) by Tunabelly Software — does the actual SMC fan control. We just orchestrate its rules.
- [Hammerspoon](https://www.hammerspoon.org/) — macOS automation framework powering the hotkey + state machine
- The `IOHIDEventSystemClient` temperature-reading approach is the same one used by [Stats](https://github.com/exelban/stats) and TG Pro itself

## License

MIT
