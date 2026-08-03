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

After installing, open TG Pro once and **grant the permissions it asks for** — the fan helper install needs your password once. The installer can't do this for you, and without that helper fan control does nothing.

Everything else (the fan-takeover switches `fanControlType` / `enableSystemOverrides`) is configured automatically by `install.sh`. To verify:

```bash
defaults read com.tunabellysoftware.tgpro fanControlType          # should be 2
defaults read com.tunabellysoftware.tgpro enableSystemOverrides   # should be (1, 1)
```

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

`cycleSteps[].type` is `auto` / `fullBlast` / `cooldown` / `temperature`. `configSensor` 0 = "Any Sensor" (works on all Macs); `configFan` 0 = "All Fans" (TG Pro's internal indices).

## Troubleshooting

### Switched to Turbo but the fan doesn't spin

In order of likelihood:

1. **The temperature hasn't reached the trigger point — usually this, not a bug.** Curves mean "temp ≥ threshold → that percentage". Turbo defaults to 0% below 30°C, 10% at 35°C, and only 50% at 40°C. An idle Mac in the mid-30s legitimately keeps the fan off. To verify:

   ```bash
   for i in 1 2 3 4; do (yes > /dev/null &); done   # load it up
   ~/.hammerspoon/readtemp                          # watch the temp climb
   pkill yes                                        # stop
   ```

2. **TG Pro isn't actually driving the fans.** The sneaky one: rules get written fine (`tgpro-rules apply` even reports success) but TG Pro sits in system-default mode and never executes them.

   ```bash
   defaults read com.tunabellysoftware.tgpro fanControlType         # 0 = system default (hands off), want 2
   defaults read com.tunabellysoftware.tgpro enableSystemOverrides  # (0, 0) = no override, want (1, 1)
   ```

   `install.sh` sets both automatically. If you do it by hand, **quit TG Pro first** — it rewrites the plist from memory on exit, so a `defaults write` while it's running gets silently rolled back:

   ```bash
   osascript -e 'quit app "TG Pro"'; sleep 3
   defaults write com.tunabellysoftware.tgpro fanControlType -int 2
   defaults write com.tunabellysoftware.tgpro enableSystemOverrides -array -int 1 -int 1
   open -ga "TG Pro"
   ```

3. **The fan helper isn't installed/authorized:**

   ```bash
   sudo launchctl print system/com.tunabellysoftware.TGFanHelper | grep 'state ='   # want running
   ```

### No mode letter (S / P / T) in the menu bar

1. **The menu bar is full and the notch ate the icon.** On notched MacBooks status items are laid out right-to-left, and whatever doesn't fit ends up underneath the notch — **it exists, you just can't see it**. `hs.menuIcon(false)` hides Hammerspoon's own hammer and frees ~30px (`HIDE_HS_MENUICON=1 ./install.sh` does it for you); beyond that, trim other items (e.g. TG Pro's second temperature and fan RPM readouts).

   Note: the `frame` Hammerspoon reports **does not account for notch occlusion** — hidden items still report normal coordinates, so you can't use coordinates to judge visibility.

2. **Hammerspoon isn't set to launch at login.** After a reboot HS never starts, so icons and hotkeys are simply gone. The installer adds the login item for you.

3. **The config wasn't really reloaded.** Running `open` against an already-running Hammerspoon just activates it and **does not reload `init.lua`**:

   ```bash
   osascript -e 'quit app "Hammerspoon"'; sleep 1; pkill -x Hammerspoon; open -ga Hammerspoon
   ```

### Hotkey works but clicking the menu bar icon does nothing

A v1.0 bug, now fixed. The click callback referenced `cycle` before its `local function cycle` declaration, so the closure captured the *global* `cycle` (`nil`) and clicking raised `attempt to call a nil value`. The hotkey was unaffected because it binds after the definition. Update to the latest version.

### The icon shows up and then disappears

`hs.menubar` / `hs.timer` objects stored in `local` variables lose their last strong reference when the chunk finishes and get collected by Lua's GC. This project keeps them global (`statusBar`). Worth remembering when writing your own Hammerspoon modules.

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
