import Foundation
import AppKit

enum SystemInfo {
    static func runShell(_ command: String) -> String {
        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments = ["-c", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isHammerspoonRunning: Bool {
        !runShell("pgrep -lf Hammerspoon").isEmpty
    }

    static var isMacsFanControlInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Macs Fan Control.app")
    }

    static var currentMfcPreset: String {
        let raw = runShell("/usr/bin/defaults read com.crystalidea.macsfancontrol ActivePreset 2>/dev/null")
        return raw
    }

    static var isFanFullBlast: Bool {
        currentMfcPreset == "Predefined:1"
    }

    static func reloadHammerspoon() {
        _ = runShell("osascript -e 'quit app \"Hammerspoon\"' 2>/dev/null; sleep 1; open -a Hammerspoon")
    }
}
