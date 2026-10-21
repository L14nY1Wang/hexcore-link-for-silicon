import AppKit
import SwiftUI
import Combine
import Foundation
import CLiana

struct DeviceInfo: Identifiable, Hashable {
    let id: String
    let product: String
    let manufacturer: String
    let vendorID: UInt16
    let productID: UInt16
    let isUSB: Bool
    let interfaceNumber: Int32
}

// Vendor model tables, mirroring the vendor preload's device filter.
private let hcxModels: [UInt16: String] = [
    41216: "FireFly",
    41624: "AnnePro 2D",
    41625: "W800",
    61445: "TENET 70",
    61449: "APX ACRYLIC M2R5",
    61696: "AKDM",
]
private let anneModels: [UInt16: String] = [41619: "ANNE PRO 2D"]

private func cString<T>(_ tuple: T, capacity: Int) -> String {
    var value = tuple
    return withUnsafePointer(to: &value) {
        $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
    }
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [DeviceInfo] = []
    @Published private(set) var connected: DeviceInfo?
    @Published private(set) var battery: Int?
    @Published private(set) var firmware: String = ""
    @Published private(set) var uptime: String = ""
    @Published private(set) var udid: String = ""
    @Published private(set) var hardwareState: String = ""
    @Published var error: String = ""
    @Published private(set) var permission: String = "unknown"
    @Published private(set) var layouts: [LayoutSummary] = []
    @Published private(set) var currentKeymap: Keymap?
    @Published var layerIndex: Int = 0
    @Published private(set) var selectedLayoutID: Int?
    @Published private(set) var deviceLayerKeys: [UInt16] = []
    @Published private(set) var deviceLayerStatus: String = ""
    @Published private(set) var brightness: Int = 50
    @Published var page: Page = .overview

    enum Page: String, CaseIterable, Identifiable {
        case overview, layout, lighting, macros, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "总览"
            case .layout: return "配列"
            case .lighting: return "灯光"
            case .macros: return "宏"
            case .settings: return "设置"
            }
        }
        var icon: String {
            switch self {
            case .overview: return "gauge"
            case .layout: return "keyboard"
            case .lighting: return "lightbulb"
            case .macros: return "record.circle"
            case .settings: return "gearshape"
            }
        }
    }

    private var keymapsByID: [Int: Keymap] = [:]

    var keyboardModel: Int { currentKeymap?.deviceModel ?? 2 }

    var layoutsForDevice: [LayoutSummary] {
        let onDevice = layouts.filter { $0.model == keyboardModel }
        return onDevice.isEmpty ? layouts : onDevice
    }

    var currentKeys: [Keycode] {
        guard let keymap = currentKeymap else { return [] }
        switch layerIndex {
        case 1: return keymap.fn1
        case 2: return keymap.fn2
        case 3: return keymap.tap
        default: return keymap.top
        }
    }

    func selectLayout(_ id: Int) {
        guard let keymap = keymapsByID[id] else { return }
        selectedLayoutID = id
        currentKeymap = keymap
    }

    struct LayoutSummary: Identifiable, Hashable {
        let id: Int
        let name: String
        let model: Int
    }

    private var handle: OpaquePointer?
    private var database: VendorDatabase?

    init() {
        if liana_init() != 0 {
            error = "HID 初始化失败"
        }
        refreshPermission()
        refresh()
        openDatabase()
        if let raw = ProcessInfo.processInfo.environment["HEXCORE_START_PAGE"],
           let start = Page(rawValue: raw) {
            page = start
        }
    }

    deinit {
        if let handle { liana_close(handle) }
    }

    func refreshPermission() {
        switch liana_check_listen_access() {
        case 1: permission = "granted"
        case 0: permission = "denied"
        default: permission = "unknown"
        }
    }

    func requestPermission() {
        _ = liana_request_listen_access()
        refreshPermission()
    }

    func refresh() {
        var buffer = [liana_device_info](repeating: liana_device_info(), count: 256)
        let count = buffer.withUnsafeMutableBufferPointer { ptr in
            liana_enumerate(ptr.baseAddress, Int32(ptr.count))
        }
        devices = buffer.prefix(Int(max(0, count))).compactMap { d -> DeviceInfo? in
            // Only the vendor's keyboards, and only the vendor-defined
            // interface (1); the others are consumer-control endpoints.
            let model: String?
            switch d.vendor_id {
            case 0x3311: model = hcxModels[d.product_id]
            case 0x0311: model = anneModels[d.product_id]
            default: model = nil
            }
            guard let model, d.interface_number == 1 else { return nil }
            return DeviceInfo(
                id: cString(d.path, capacity: Int(LIANA_PATH_MAX)),
                product: model,
                manufacturer: cString(d.manufacturer, capacity: Int(LIANA_STRING_MAX)),
                vendorID: d.vendor_id,
                productID: d.product_id,
                isUSB: d.is_usb != 0,
                interfaceNumber: d.interface_number
            )
        }

        // Single keyboard: connect immediately so the window shows live data.
        if devices.count == 1, connected == nil, let only = devices.first {
            connect(only)
        }
    }

    private func openDatabase() {
        let path = NSHomeDirectory() + "/Library/Application Support/hexcore-link/hexcore-link.db"
        guard FileManager.default.fileExists(atPath: path),
              let database = VendorDatabase(path: path) else { return }
        self.database = database
        var items: [LayoutSummary] = []
        for model in database.deviceModels() {
            for row in database.keymaps(deviceModel: model) {
                guard let id = row["id"] as? Int64, let name = row["name"] as? String else { continue }
                let summary = LayoutSummary(id: Int(id), name: name, model: model)
                items.append(summary)
                if let keymap = Keymap.parse(row: row) {
                    keymapsByID[summary.id] = keymap
                }
            }
        }
        layouts = items
        // The Anne Pro 2D uses device model 2; show its QWERTY layout first.
        if let match = items.first(where: { $0.model == 2 && $0.name == "intl.keymap.qwerty" }) {
            selectedLayoutID = match.id
            currentKeymap = keymapsByID[match.id]
        } else if let first = items.first {
            selectedLayoutID = first.id
            currentKeymap = keymapsByID[first.id]
        }
    }

    func readDeviceLayer() {
        guard let handle else { return }
        var buffer = [UInt8](repeating: 0, count: 1024)
        var request: [UInt8] = [UInt8(layerIndex)]
        let length = buffer.withUnsafeMutableBufferPointer { out in
            request.withUnsafeBufferPointer { req in
                liana_read_command_payload(handle, "readKeyboardLayer", 3,
                                           req.baseAddress, 1, out.baseAddress, out.count, 2000)
            }
        }
        guard length > 1 else {
            deviceLayerKeys = []
            deviceLayerStatus = "设备无回复"
            return
        }
        var keys: [UInt16] = []
        for i in stride(from: 0, to: Int(length) - 1, by: 2) {
            keys.append(UInt16(buffer[i]) | (UInt16(buffer[i + 1]) << 8))
        }
        deviceLayerKeys = keys
        deviceLayerStatus = "读取 \(keys.count) 键"
    }

    func previewColor(_ color: Color) {
        guard let handle else { return }
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        let payload: [UInt8] = [
            1, 255,
            UInt8(max(0, min(255, ns.redComponent * 255))),
            UInt8(max(0, min(255, ns.greenComponent * 255))),
            UInt8(max(0, min(255, ns.blueComponent * 255))),
        ]
        _ = payload.withUnsafeBufferPointer {
            liana_write(handle, "previewLight", $0.baseAddress, payload.count, 0)
        }
        deviceLayerStatus = "已预览颜色"
    }

    func setBrightness(_ value: Int) {
        guard let handle else { return }
        let level = max(0, min(100, value))
        var payload: [UInt8] = [UInt8(level)]
        _ = payload.withUnsafeBufferPointer {
            liana_write(handle, "backlightBrightness", $0.baseAddress, 1, 3)
        }
        brightness = level
    }

    func applyCurrentLayer() {
        guard let handle, !currentKeys.isEmpty else { return }
        var payload: [UInt8] = [UInt8(layerIndex)]
        for key in currentKeys {
            let raw = UInt16(key.raw)
            payload.append(UInt8(raw & 0xff))
            payload.append(UInt8(raw >> 8))
        }
        let rc = payload.withUnsafeBufferPointer {
            liana_write(handle, "writeKeyboardLayer", $0.baseAddress, payload.count, 3)
        }
        deviceLayerStatus = rc == 0
            ? "已写入 \(currentKeys.count) 键到层 \(layerIndex)"
            : "写入失败"
    }

    func connect(_ device: DeviceInfo) {
        disconnect()
        guard let h = liana_open(device.id, device.isUSB ? 1 : 0, Int32(device.vendorID)) else {
            error = "无法打开 \(device.product)"
            return
        }
        handle = h
        connected = device
        error = ""
        readAll()
    }

    func disconnect() {
        if let handle { liana_close(handle) }
        handle = nil
        connected = nil
        battery = nil
        firmware = ""
        uptime = ""
        udid = ""
        hardwareState = ""
    }

    func readAll() {
        guard handle != nil else { return }
        readFirmware()
        readBattery()
        readUptime()
        readUDID()
        readHardwareState()
    }

    private func transact(_ command: String) -> [UInt8]? {
        guard let handle else { return nil }
        var reply = [UInt8](repeating: 0, count: 64)
        let n = reply.withUnsafeMutableBufferPointer { ptr in
            liana_transact(handle, command, nil, 0, 3, ptr.baseAddress, ptr.count, 1200)
        }
        guard n > 0 else { return nil }
        return Array(reply.prefix(Int(n)))
    }

    private func readFirmware() {
        guard let data = transact("readFirmwareVersion"), data.count >= 3 else {
            firmware = "无回复"
            return
        }
        // Six bytes: key major/minor, LED major/minor, BLE major/minor.
        guard data.count >= 6 else {
            firmware = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            return
        }
        firmware = "key \(data[0]).\(data[1]) · led \(data[2]).\(data[3]) · ble \(data[4]).\(data[5])"
    }

    private func readBattery() {
        guard let data = transact("readBatteryPercentage"), let first = data.first else {
            battery = nil
            return
        }
        battery = first == 0xff ? nil : Int(first)
    }

    private func readUptime() {
        guard let data = transact("readPowerOnTime"), data.count >= 4 else {
            uptime = "无回复"
            return
        }
        let seconds = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        uptime = String(format: "%dh %02dm %02ds", h, m, seconds % 60)
    }

    private func readUDID() {
        guard let data = transact("readUDID"), !data.isEmpty else {
            udid = "无回复"
            return
        }
        udid = data.map { String(format: "%02X", $0) }.joined()
    }

    private func readHardwareState() {
        guard let data = transact("readHardwareState"), !data.isEmpty else {
            hardwareState = "无回复"
            return
        }
        hardwareState = data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
