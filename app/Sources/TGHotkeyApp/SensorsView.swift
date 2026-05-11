import SwiftUI

/// 实时显示所有 IOHIDEventSystemClient 暴露的温度传感器（通过 readtemp --list）。
struct SensorsView: View {
    @State private var sensors: [(name: String, value: Double)] = []
    @State private var lastUpdate = Date()
    @State private var refreshTask: Task<Void, Never>?
    @State private var sortByValue = true
    @State private var filter = ""

    private let readtempPath = NSString(string: "~/.hammerspoon/readtemp").expandingTildeInPath

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("温度传感器实时监控")
                    .font(.title2).bold()
                Spacer()
                Text("最后刷新 \(lastUpdate, style: .time)")
                    .font(.caption).foregroundColor(.secondary)
            }

            HStack {
                TextField("过滤名字（如 'PMU'、'CPU'、'GPU'）", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Toggle("按温度排序", isOn: $sortByValue)
                Spacer()
                Text("共 \(sensors.count) 个 sensor")
                    .font(.caption).foregroundColor(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(displayedSensors.enumerated()), id: \.offset) { _, item in
                        sensorRow(name: item.0, value: item.1)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.gray.opacity(0.06))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("注：本页只是查看。规则用的 sensor 索引在 Settings 标签 → 每档 Temperature → 「参考 Sensor」里设。本工具的 readtemp 跟 TG Pro 的 sensor 索引不一一对应（TG Pro 的索引是它内部加密的映射）。")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { startRefreshing() }
        .onDisappear { refreshTask?.cancel() }
    }

    private func sensorRow(name: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 280, alignment: .leading)
            // 温度条
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(for: value))
                        .frame(width: g.size.width * CGFloat(min(max(value / 100.0, 0), 1)))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f °C", value))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(barColor(for: value))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func barColor(for v: Double) -> Color {
        switch v {
        case ..<40:    return .green
        case 40..<60:  return .yellow
        case 60..<80:  return .orange
        default:       return .red
        }
    }

    private var displayedSensors: [(String, Double)] {
        let filtered = filter.isEmpty
            ? sensors
            : sensors.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        let sorted = sortByValue
            ? filtered.sorted { $0.value > $1.value }
            : filtered.sorted { $0.name < $1.name }
        return sorted.map { ($0.name, $0.value) }
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 秒
            }
        }
    }

    private func refresh() {
        let task = Process()
        task.launchPath = readtempPath
        task.arguments = ["--list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }
        var parsed: [(String, Double)] = []
        for line in text.split(separator: "\n") {
            // 行格式: "  PMU tdie1                       45.48"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let lastSpace = trimmed.range(of: " ", options: .backwards) else { continue }
            let name = String(trimmed[..<lastSpace.lowerBound]).trimmingCharacters(in: .whitespaces)
            let valStr = String(trimmed[lastSpace.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let v = Double(valStr), !name.isEmpty {
                parsed.append((name, v))
            }
        }
        if !parsed.isEmpty {
            DispatchQueue.main.async {
                sensors = parsed
                lastUpdate = Date()
            }
        }
    }
}
