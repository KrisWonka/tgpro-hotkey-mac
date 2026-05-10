import SwiftUI

struct SettingsView: View {
    @Binding var config: TGHotkeyConfig
    @State private var saveStatus: SaveStatus = .idle
    @State private var expandedStepIDs: Set<UUID> = []

    enum SaveStatus { case idle, saving, saved, error(String) }

    @State private var autostart: Bool = Autostart.isEnabled

    var body: some View {
        Form {
            Section("开机自启") {
                Toggle("登录时自动启动 Hammerspoon + TG Pro", isOn: Binding(
                    get: { autostart },
                    set: { v in autostart = v; Autostart.setEnabled(v) }
                ))
                Text("写一个 LaunchAgent 到 ~/Library/LaunchAgents/com.kriswonka.tghotkey.autostart.plist。系统启动后两个 app 后台启动，无窗口闪现。关闭即删 plist。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("快捷键") {
                Toggle("启用全局快捷键", isOn: $config.hotkeyEnabled)
                HStack {
                    Text("组合键")
                    HotkeyRecorder(mods: $config.hotkeyMods, key: $config.hotkeyKey)
                }
                .disabled(!config.hotkeyEnabled)
                Text("点上方按钮 → 按一下组合键即可绑定（ESC 取消）。修饰键 ⌃⌥⇧⌘ 至少要有一个。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("循环档位（按 \(hotkeyDescription) 在档位间循环）") {
                cycleStepsList
                addStepMenu
                Text("点档位左侧 ▶ 三角展开改名 / 调参数。Cooldown 档：全速直到平均温度降到目标值后自动回 Auto。Full Blast 档：可设 N 分钟后自动回 Auto。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("提示") {
                Toggle("启用屏幕中央提示", isOn: $config.alertEnabled)
                HStack {
                    Text("Cooldown 结束文字")
                        .frame(width: 130, alignment: .leading)
                    TextField("Cooldown done ✓", text: $config.alertCooldownDone)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!config.alertEnabled)
                HStack {
                    Text("显示时长")
                        .frame(width: 130, alignment: .leading)
                    Slider(value: $config.alertDuration, in: 0.3...3.0, step: 0.1)
                    Text("\(String(format: "%.1f", config.alertDuration)) 秒")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .disabled(!config.alertEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    statusBadge
                    Button("保存并重载") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    @ViewBuilder
    private var cycleStepsList: some View {
        if config.cycleSteps.isEmpty {
            Text("（空 — 至少加一档才能使用快捷键）")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(config.cycleSteps.indices, id: \.self) { idx in
                    cycleStepCard(idx: idx)
                }
            }
        }
    }

    private func cycleStepCard(idx: Int) -> some View {
        let stepBinding = $config.cycleSteps[idx]
        let step = config.cycleSteps[idx]
        let isExpanded = Binding<Bool>(
            get: { expandedStepIDs.contains(step.id) },
            set: { v in
                if v { expandedStepIDs.insert(step.id) } else { expandedStepIDs.remove(step.id) }
            }
        )

        return VStack(spacing: 0) {
            DisclosureGroup(isExpanded: isExpanded) {
                stepDetails(idx: idx, step: stepBinding)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            } label: {
                HStack(spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    Image(systemName: step.type.icon)
                        .frame(width: 22)
                        .foregroundColor(.accentColor)
                    Text(step.effectiveName)
                        .font(.body)
                    if !step.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("(\(step.type.displayName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    rowButtons(idx: idx)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
    }

    private func rowButtons(idx: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                guard idx > 0 else { return }
                config.cycleSteps.swapAt(idx, idx - 1)
            } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(idx == 0)
                .help("上移")

            Button {
                guard idx < config.cycleSteps.count - 1 else { return }
                config.cycleSteps.swapAt(idx, idx + 1)
            } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(idx == config.cycleSteps.count - 1)
                .help("下移")

            Button {
                let removed = config.cycleSteps.remove(at: idx)
                expandedStepIDs.remove(removed.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red.opacity(0.75))
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
    }

    @ViewBuilder
    private func stepDetails(idx: Int, step: Binding<CycleStep>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("名字")
                    .frame(width: 80, alignment: .leading)
                TextField(step.wrappedValue.type.displayName, text: step.name)
                    .textFieldStyle(.roundedBorder)
            }

            switch step.wrappedValue.type {
            case .auto:
                Text("Auto 档清空 TG Pro 的 Auto Max Rules，回到系统默认温控")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .fullBlast:
                Toggle("到点自动回 Auto", isOn: step.autoRevertEnabled)
                HStack {
                    Text("回切倒计时")
                        .frame(width: 80, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(step.wrappedValue.autoRevertSec) / 60.0 },
                            set: { step.wrappedValue.autoRevertSec = Int($0 * 60) }
                        ),
                        in: 1...60, step: 1
                    )
                    Text("\(step.wrappedValue.autoRevertSec / 60) 分钟")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .disabled(!step.wrappedValue.autoRevertEnabled)
            case .cooldown:
                HStack {
                    Text("目标温度")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: step.cooldownTargetTemp, in: 30...70, step: 1)
                    Text("\(Int(step.wrappedValue.cooldownTargetTemp)) °C")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text("轮询间隔")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: step.cooldownPollSec, in: 1...30, step: 1)
                    Text("\(Int(step.wrappedValue.cooldownPollSec)) 秒")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
            case .temperature:
                temperatureCurveEditor(step: step)
            }
        }
    }

    @ViewBuilder
    private func temperatureCurveEditor(step: Binding<CycleStep>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("曲线（拖拽调点；右键删除）")
                    .font(.subheadline).bold()
                Spacer()
                Button {
                    let last = step.wrappedValue.curve.last
                    let newT = min(90.0, (last?.temperatureLimit ?? 40) + 10)
                    let newP = min(100, (last?.percent ?? 30) + 15)
                    var arr = step.wrappedValue.curve
                    arr.append(CurvePoint(temperatureLimit: newT, percent: newP))
                    arr.sort { $0.temperatureLimit < $1.temperatureLimit }
                    step.wrappedValue.curve = arr
                } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
                    .help("加一个点")
                Menu("载入预设") {
                    ForEach(CurveTemplate.allCases) { tmpl in
                        Button(tmpl.displayName) { step.wrappedValue.curve = tmpl.points }
                    }
                }
                .frame(maxWidth: 100)
            }
            FanCurveEditor(curve: step.curve)
                .background(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            Text("""
                X 轴 20–90°C（5°C 一格） · Y 轴 0–100%（5% 一格）+ 底部 Stop 档（橙色）。
                百分比是相对于风扇 RPM 范围（0% = 硬件最低 RPM ≈ 2317；100% = max ≈ 7826）。
                把点拖到 Stop 区表示该温度无规则，让系统自动控制（风扇可彻底停转）。
                """)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addStepMenu: some View {
        HStack {
            Menu {
                ForEach(CycleStepType.allCases) { t in
                    Button {
                        let new = CycleStep(type: t)
                        config.cycleSteps.append(new)
                        expandedStepIDs.insert(new.id)
                    } label: {
                        Label(t.displayName, systemImage: t.icon)
                    }
                }
            } label: {
                Label("添加档位", systemImage: "plus")
            }
            .frame(maxWidth: 140)
            Spacer()
            Text("用 ↑↓ 调整顺序")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var hotkeyDescription: String {
        let modSyms = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
        let mods = config.hotkeyMods.compactMap { modSyms[$0] }.joined()
        return "\(mods)\(config.hotkeyKey.uppercased())"
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView().controlSize(.small)
        case .saved:
            Label("已保存", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red)
        }
    }

    private func save() {
        saveStatus = .saving
        DispatchQueue.global().async {
            do {
                try config.save()
                SystemInfo.reloadHammerspoon()
                DispatchQueue.main.async {
                    saveStatus = .saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if case .saved = saveStatus { saveStatus = .idle }
                    }
                }
            } catch {
                DispatchQueue.main.async { saveStatus = .error(error.localizedDescription) }
            }
        }
    }
}
