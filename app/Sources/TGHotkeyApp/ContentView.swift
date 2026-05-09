import SwiftUI

struct ContentView: View {
    @State private var config: TGHotkeyConfig = TGHotkeyConfig.load()

    var body: some View {
        TabView {
            SettingsView(config: $config)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            StatusView()
                .tabItem { Label("Status", systemImage: "fan") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 720, minHeight: 600)
        .padding(.top, 4)
    }
}

struct StatusView: View {
    @State private var presetRaw: String = ""
    @State private var hsRunning: Bool = false
    @State private var mfcInstalled: Bool = false
    @State private var refreshTick: Int = 0

    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("当前状态").font(.title2).bold()

            statusRow(
                label: "Macs Fan Control 已安装",
                ok: mfcInstalled,
                detail: mfcInstalled ? "/Applications/Macs Fan Control.app" : "未检测到 — 请用 brew install --cask macs-fan-control"
            )

            statusRow(
                label: "Hammerspoon 运行中",
                ok: hsRunning,
                detail: hsRunning ? "已加载 fan-hotkey.lua" : "未运行 — 启动 Hammerspoon 才能用快捷键"
            )

            statusRow(
                label: "风扇预设",
                ok: !presetRaw.isEmpty,
                detail: prettyPreset()
            )

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        presetRaw = SystemInfo.currentMfcPreset
        hsRunning = SystemInfo.isHammerspoonRunning
        mfcInstalled = SystemInfo.isMacsFanControlInstalled
        refreshTick += 1
    }

    private func prettyPreset() -> String {
        switch presetRaw {
        case "Predefined:0": return "Auto（系统自动控速）"
        case "Predefined:1": return "Full Blast（全速）🌀"
        case "": return "未读到 — Macs Fan Control 可能没装或没运行过"
        default: return presetRaw
        }
    }

    @ViewBuilder
    private func statusRow(label: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fan.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
            Text("TG Hotkey")
                .font(.largeTitle).bold()
            Text("一键 Macs Fan Control「全速 ↔ 自动」 + 自动回切")
                .foregroundColor(.secondary)
            Link("github.com/KrisWonka/fan-hotkey-mac",
                 destination: URL(string: "https://github.com/KrisWonka/fan-hotkey-mac")!)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
