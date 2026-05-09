import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorder: View {
    @Binding var mods: [String]
    @Binding var key: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                if recording {
                    Text("按下要绑定的组合键…")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text(displayString.isEmpty ? "未设置" : displayString)
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                Image(systemName: recording ? "circle.fill" : "pencil")
                    .foregroundColor(recording ? .red : .secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(recording ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private var displayString: String {
        var parts: [String] = []
        if mods.contains("ctrl")  { parts.append("⌃") }
        if mods.contains("alt")   { parts.append("⌥") }
        if mods.contains("shift") { parts.append("⇧") }
        if mods.contains("cmd")   { parts.append("⌘") }
        if !key.isEmpty { parts.append(key.uppercased()) }
        return parts.joined()
    }

    private func toggle() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        var newMods: [String] = []
        let f = event.modifierFlags
        if f.contains(.control)  { newMods.append("ctrl") }
        if f.contains(.option)   { newMods.append("alt") }
        if f.contains(.shift)    { newMods.append("shift") }
        if f.contains(.command)  { newMods.append("cmd") }

        guard !newMods.isEmpty else { return }
        guard let keyStr = keyString(for: event) else { return }

        mods = newMods
        key = keyStr
        stopRecording()
    }

    private func keyString(for event: NSEvent) -> String? {
        let specialKeys: [Int: String] = [
            kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4",
            kVK_F5: "f5", kVK_F6: "f6", kVK_F7: "f7", kVK_F8: "f8",
            kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
            kVK_Space: "space", kVK_Return: "return", kVK_Tab: "tab",
            kVK_Delete: "delete", kVK_ForwardDelete: "forwarddelete",
            kVK_LeftArrow: "left", kVK_RightArrow: "right",
            kVK_UpArrow: "up", kVK_DownArrow: "down",
            kVK_Escape: "escape",
        ]
        if let s = specialKeys[Int(event.keyCode)] { return s }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.lowercased()
        }
        return nil
    }
}
