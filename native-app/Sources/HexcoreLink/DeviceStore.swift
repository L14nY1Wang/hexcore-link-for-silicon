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
                items.append(LayoutSummary(id: Int(id), name: name, model: model))
            }
        }
        layouts = items
        // The Anne Pro 2D uses device model 2; show its QWERTY layout first.
        if let row = database.keymaps(deviceModel: 2).first(where: { ($0["name"] as? String) == "intl.keymap.qwerty" }) {
            currentKeymap = Keymap.parse(row: row)
        } else {
            currentKeymap = database.keymaps(deviceModel: 2).first.flatMap(Keymap.parse(row:))
        }
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
