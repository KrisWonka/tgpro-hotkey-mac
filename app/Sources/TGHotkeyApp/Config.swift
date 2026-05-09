import Foundation

enum CycleStepType: String, Codable, CaseIterable, Identifiable {
    case auto
    case fullBlast
    case cooldown
    case temperature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:        return "Auto"
        case .fullBlast:   return "Full Blast"
        case .cooldown:    return "Cooldown"
        case .temperature: return "Temperature"
        }
    }

    var icon: String {
        switch self {
        case .auto:        return "leaf.fill"
        case .fullBlast:   return "wind"
        case .cooldown:    return "snowflake"
        case .temperature: return "thermometer.medium"
        }
    }
}

struct CurvePoint: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var temperatureLimit: Double  // °C
    var percent: Int              // 0-100

    enum CodingKeys: String, CodingKey {
        case temperatureLimit, percent
    }
}

enum CurveTemplate: String, CaseIterable, Identifiable {
    case silence, performance, turbo, empty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .silence:     return "Silence"
        case .performance: return "Performance"
        case .turbo:       return "Turbo"
        case .empty:       return "Empty"
        }
    }

    var points: [CurvePoint] {
        switch self {
        case .silence:
            return [
                CurvePoint(temperatureLimit: 30, percent: 0),
                CurvePoint(temperatureLimit: 40, percent: 0),
                CurvePoint(temperatureLimit: 50, percent: 20),
                CurvePoint(temperatureLimit: 60, percent: 35),
                CurvePoint(temperatureLimit: 70, percent: 50),
                CurvePoint(temperatureLimit: 80, percent: 70),
                CurvePoint(temperatureLimit: 90, percent: 100),
            ]
        case .performance:
            return [
                CurvePoint(temperatureLimit: 30, percent: 0),
                CurvePoint(temperatureLimit: 40, percent: 0),
                CurvePoint(temperatureLimit: 50, percent: 25),
                CurvePoint(temperatureLimit: 60, percent: 60),
                CurvePoint(temperatureLimit: 70, percent: 75),
                CurvePoint(temperatureLimit: 80, percent: 90),
                CurvePoint(temperatureLimit: 90, percent: 100),
            ]
        case .turbo:
            return [
                CurvePoint(temperatureLimit: 20, percent: 0),
                CurvePoint(temperatureLimit: 30, percent: 0),
                CurvePoint(temperatureLimit: 45, percent: 0),
                CurvePoint(temperatureLimit: 50, percent: 35),
                CurvePoint(temperatureLimit: 60, percent: 95),
                CurvePoint(temperatureLimit: 70, percent: 100),
                CurvePoint(temperatureLimit: 80, percent: 100),
                CurvePoint(temperatureLimit: 90, percent: 100),
            ]
        case .empty:
            return []
        }
    }
}

struct CycleStep: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: CycleStepType
    var name: String = ""

    // Cooldown 专属
    var cooldownTargetTemp: Double = 40
    var cooldownPollSec: Double = 3

    // Full Blast 专属
    var autoRevertEnabled: Bool = false
    var autoRevertSec: Int = 600

    // Temperature 专属
    var curve: [CurvePoint] = []
    var configSensor: Int = 4   // 4 = Highest CPU
    var configFan: Int = 0      // 0 = All Fans

    var effectiveName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? type.displayName : name
    }
}

struct TGHotkeyConfig: Codable, Equatable {
    var hotkeyEnabled: Bool = true
    var hotkeyMods: [String] = ["ctrl", "alt", "cmd"]
    var hotkeyKey: String = "8"

    var alertEnabled: Bool = true
    var alertDuration: Double = 1.2
    var alertCooldownDone: String = "Cooldown done ✓"

    var cycleSteps: [CycleStep] = [
        CycleStep(type: .auto),
        CycleStep(type: .temperature, name: "Silence",     curve: CurveTemplate.silence.points),
        CycleStep(type: .temperature, name: "Performance", curve: CurveTemplate.performance.points),
        CycleStep(type: .temperature, name: "Turbo",       curve: CurveTemplate.turbo.points),
        CycleStep(type: .cooldown),
    ]

    static let configPath: String = {
        NSString(string: "~/.hammerspoon/tgpro-hotkey-config.json").expandingTildeInPath
    }()

    static func load() -> TGHotkeyConfig {
        let url = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(TGHotkeyConfig.self, from: data)
        else {
            return TGHotkeyConfig()
        }
        return cfg
    }

    func save() throws {
        let url = URL(fileURLWithPath: Self.configPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
