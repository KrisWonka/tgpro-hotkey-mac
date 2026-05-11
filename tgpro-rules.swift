// tgpro-rules — 写规则到 TG Pro 的 Auto Max Rules + 重启 TG Pro
//
// 用法:
//   tgpro-rules apply         从 stdin 读 JSON 应用规则
//   tgpro-rules clear         清空所有规则
//   tgpro-rules current       dump 当前 plist 里的规则
//
// JSON 输入格式:
//   {
//     "rules": [
//       {"percent": 30, "temperatureLimit": 50.0, "configSensor": 4, "configFan": 0},
//       {"percent": 80, "temperatureLimit": 75.0, "configSensor": 4, "configFan": 0}
//     ]
//   }
//
// 编译: swiftc tgpro-rules.swift -o tgpro-rules

import Foundation

// 必须 @objc 注解 + 类名严格对应，让 NSKeyedArchive 写出 "AutoBoostConfigModel"
@objc(AutoBoostConfigModel)
class AutoBoostConfigModel: NSObject, NSCoding {
    var percent: Int = 100
    var temperatureLimit: Double = 0
    var isForBatteryPower: Bool = false
    var configSensor: Int = 0   // 默认 Any Sensor（Auto Boost 模式下 4 不一定对应 Highest CPU）
    var configFan: Int = 0      // 默认 All Fans
    var isEnabled: Bool = true

    init(percent: Int, temp: Double, sensor: Int, fan: Int, isBattery: Bool) {
        self.percent = percent
        self.temperatureLimit = temp
        self.configSensor = sensor
        self.configFan = fan
        self.isForBatteryPower = isBattery
        super.init()
    }

    required init?(coder: NSCoder) {
        percent = coder.decodeInteger(forKey: "percent")
        temperatureLimit = coder.decodeDouble(forKey: "temperatureLimit")
        isForBatteryPower = coder.decodeBool(forKey: "isForBatteryPower")
        configSensor = coder.decodeInteger(forKey: "configSensor")
        configFan = coder.decodeInteger(forKey: "configFan")
        isEnabled = coder.decodeBool(forKey: "isEnabled")
    }

    func encode(with coder: NSCoder) {
        coder.encode(percent, forKey: "percent")
        coder.encode(temperatureLimit, forKey: "temperatureLimit")
        coder.encode(isForBatteryPower, forKey: "isForBatteryPower")
        coder.encode(configSensor, forKey: "configSensor")
        coder.encode(configFan, forKey: "configFan")
        coder.encode(isEnabled, forKey: "isEnabled")
    }
}

let plistPath = NSString(string: "~/Library/Preferences/com.tunabellysoftware.tgpro.plist").expandingTildeInPath

func bail(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write("✗ \(msg)\n".data(using: .utf8)!)
    exit(code)
}

func loadPrefs() -> NSMutableDictionary {
    guard let p = NSMutableDictionary(contentsOfFile: plistPath) else {
        bail("读不到 \(plistPath)。请先打开过 TG Pro。")
    }
    return p
}

func savePrefs(_ prefs: NSMutableDictionary) {
    if !prefs.write(toFile: plistPath, atomically: true) {
        bail("写 plist 失败")
    }
}

func archiveRules(_ rules: [AutoBoostConfigModel]) -> Data {
    do {
        return try NSKeyedArchiver.archivedData(
            withRootObject: NSArray(array: rules),
            requiringSecureCoding: false
        )
    } catch {
        bail("archive 失败: \(error)")
    }
}

/// 写 prefs + 重启 TG Pro。TG Pro 的菜单栏图标已被我们永久关掉（showFanInMenuBar=false），
/// 所以重启对用户完全无感（没有图标可闪）。状态显示由 Hammerspoon 自己的单字母 item 负责。
func writePrefs(_ values: [String: Any]) {
    let bundleID = "com.tunabellysoftware.tgpro" as CFString
    for (key, val) in values {
        CFPreferencesSetValue(key as CFString, val as CFPropertyList,
                              bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    CFPreferencesAppSynchronize(bundleID)
}

func restartTGPro() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", """
      /usr/bin/osascript -e 'quit app "TG Pro"' >/dev/null 2>&1
      for i in $(seq 1 30); do
        /usr/bin/pgrep -f "/Applications/TG Pro.app/Contents/MacOS/TG Pro" >/dev/null || break
        sleep 0.1
      done
      /usr/bin/open -gja "/Applications/TG Pro.app"
    """]
    task.launch()
    task.waitUntilExit()
}

// ---- subcommand ----
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: tgpro-rules [apply | clear | current]")
    exit(2)
}

switch args[1] {

case "current":
    let prefs = loadPrefs()
    for (label, key) in [("PowerAdapter", "autoConfigsPowerAdapter"), ("Battery", "autoConfigsBattery")] {
        guard let raw = prefs[key] as? Data else { print("\(label): (none)"); continue }
        let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: raw)
        unarchiver?.requiresSecureCoding = false
        if let arr = unarchiver?.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [AutoBoostConfigModel] {
            print("--- \(label): \(arr.count) rule(s) ---")
            for (i, r) in arr.enumerated() {
                print(String(format: "  %d. %d%% when sensor#%d > %.1f°C  (fan=%d, enabled=%@)",
                             i+1, r.percent, r.configSensor, r.temperatureLimit, r.configFan,
                             r.isEnabled ? "y" : "n"))
            }
        } else {
            print("\(label): (decode failed)")
        }
    }

case "clear":
    writePrefs([
        "autoConfigsPowerAdapter": archiveRules([]),
        "autoConfigsBattery": archiveRules([]),
        "useManualInsteadOfMax": false,
        "useAutoBoostInsteadOfAutoMax": false,
        "showFanInMenuBar": false,  // 永远不显示 TG Pro 自己图标，无闪
    ])
    restartTGPro()
    print("✓ 清空规则 + 关 Auto Boost + 关 TG Pro 菜单栏图标 + 重启")

case "apply":
    // 从 stdin 读 JSON
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rulesJson = json["rules"] as? [[String: Any]] else {
        bail("stdin JSON 格式错误，期望 {\"rules\": [...]}")
    }
    var powerRules: [AutoBoostConfigModel] = []
    var batteryRules: [AutoBoostConfigModel] = []
    for r in rulesJson {
        let percent = r["percent"] as? Int ?? 100
        let temp = (r["temperatureLimit"] as? Double) ?? Double(r["temperatureLimit"] as? Int ?? 0)
        let sensor = r["configSensor"] as? Int ?? 0
        let fan = r["configFan"] as? Int ?? 0
        powerRules.append(AutoBoostConfigModel(
            percent: percent, temp: temp, sensor: sensor, fan: fan, isBattery: false))
        batteryRules.append(AutoBoostConfigModel(
            percent: percent, temp: temp, sensor: sensor, fan: fan, isBattery: true))
    }
    writePrefs([
        "autoConfigsPowerAdapter": archiveRules(powerRules),
        "autoConfigsBattery": archiveRules(batteryRules),
        "useManualInsteadOfMax": false,
        "useAutoBoostInsteadOfAutoMax": true,
        "showFanInMenuBar": false,  // 永远不显示 TG Pro 自己图标，无闪
    ])
    restartTGPro()
    print("✓ 应用 \(powerRules.count) 条规则 + 重启 TG Pro（图标已隐藏，无闪）")

default:
    bail("未知子命令: \(args[1])")
}
