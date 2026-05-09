import Foundation

/// 用 LaunchAgent 实现开机自启 Hammerspoon + TG Pro。
/// 走 `~/Library/LaunchAgents/`，纯用户域，不需要 sudo / 不需要任何 TCC 权限。
struct Autostart {
    static let label = "com.kriswonka.tghotkey.autostart"

    static var plistPath: String {
        let dir = NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
        return "\(dir)/\(label).plist"
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled { enable() } else { disable() }
    }

    private static func enable() {
        let dir = NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>RunAtLoad</key><true/>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>-c</string>
                <string>/usr/bin/open -ga Hammerspoon; /usr/bin/open -gja "TG Pro"</string>
            </array>
        </dict>
        </plist>
        """
        try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        runLaunchctl(["bootout",   "gui/\(getuid())", plistPath])  // 幂等卸一下避免冲突
        runLaunchctl(["bootstrap", "gui/\(getuid())", plistPath])
    }

    private static func disable() {
        runLaunchctl(["bootout", "gui/\(getuid())", plistPath])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let t = Process()
        t.launchPath = "/bin/launchctl"
        t.arguments = args
        t.standardOutput = Pipe()
        t.standardError = Pipe()
        do { try t.run(); t.waitUntilExit(); return t.terminationStatus }
        catch { return -1 }
    }
}
