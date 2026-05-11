// readtemp — 读 Apple Silicon Mac 上的温度传感器
// 通过私有 IOHIDEventSystemClient API（和 Macs Fan Control / Stats 等监控 App 走同一套）
//
// 用法:
//   readtemp           输出 CPU 平均温度（°C），形如 "47.32"
//   readtemp --list    列出所有 sensor 名称 + 当前温度
//   readtemp --json    JSON 输出 {sensor_name: temp, ...}
//
// 编译: swiftc readtemp.swift -framework IOKit -o readtemp

import Foundation
import IOKit

// ---- 私有 API 声明（IOKit 内部符号）----
@_silgen_name("IOHIDEventSystemClientCreate")
func _IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
func _IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
func _IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
func _IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
func _IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int64, _ flags: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
func _IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

// ---- HID 常量 ----
let kHIDPage_AppleVendor: Int32 = 0xff00
let kHIDUsage_AppleVendor_TemperatureSensor: Int32 = 0x0005
let kIOHIDEventTypeTemperature: Int64 = 15
let kIOHIDEventFieldTemperatureLevel: Int32 = (Int32(kIOHIDEventTypeTemperature) << 16)

// ---- 读所有温度传感器 ----
func readSensors() -> [(name: String, value: Double)] {
    guard let clientUM = _IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return [] }
    let client = clientUM.takeRetainedValue()

    let matching: [String: Any] = [
        "PrimaryUsagePage": kHIDPage_AppleVendor,
        "PrimaryUsage":     kHIDUsage_AppleVendor_TemperatureSensor,
    ]
    _ = _IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

    guard let services = _IOHIDEventSystemClientCopyServices(client) as? [CFTypeRef] else { return [] }

    var out: [(String, Double)] = []
    for svc in services {
        guard let nameRef = _IOHIDServiceClientCopyProperty(svc, "Product" as CFString),
              let name    = nameRef as? String,
              let evUM    = _IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0) else { continue }
        let event = evUM.takeRetainedValue()
        let v = _IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
        if v.isFinite && v > 0 { out.append((name, v)) }
    }
    return out
}

// ---- 取 CPU 相关 sensor 平均（M 系列上常见前缀）----
func cpuAverage(_ sensors: [(name: String, value: Double)]) -> Double? {
    let cpu = sensors.filter { s in
        let n = s.name.lowercased()
        // Apple Silicon: pACC0…pACC5 (P-core 簇), eACC (E-core 簇), PMU* / TG*
        return n.contains("pacc") || n.contains("eacc") || n.contains("cpu")
            || n.contains("pmu") || n.hasPrefix("tg") || n.hasPrefix("tp")
    }
    let pool = cpu.isEmpty ? sensors : cpu
    guard !pool.isEmpty else { return nil }
    return pool.map { $0.value }.reduce(0, +) / Double(pool.count)
}

// 同名 sensor 出现多次时合并并取均值（M 系列上 IOHID 经常重复 expose 同一物理 sensor）
func dedup(_ arr: [(name: String, value: Double)]) -> [(name: String, value: Double)] {
    var groups: [String: [Double]] = [:]
    for s in arr { groups[s.name, default: []].append(s.value) }
    return groups.map { (name: $0.key, value: $0.value.reduce(0,+) / Double($0.value.count)) }
}

// ---- 主流程 ----
let sensors = dedup(readSensors())
let mode = CommandLine.arguments.dropFirst().first ?? "avg"

switch mode {
case "--list":
    for s in sensors.sorted(by: { $0.name < $1.name }) {
        print(String(format: "%-32@ %6.2f", s.name as NSString, s.value))
    }
case "--json":
    var dict: [String: Double] = [:]
    for s in sensors { dict[s.name] = s.value }
    let data = try JSONSerialization.data(
        withJSONObject: dict,
        options: [.sortedKeys, .prettyPrinted]
    )
    print(String(data: data, encoding: .utf8) ?? "{}")
default:
    guard let avg = cpuAverage(sensors) else {
        FileHandle.standardError.write("no temperature sensors found\n".data(using: .utf8)!)
        exit(2)
    }
    print(String(format: "%.2f", avg))
}
