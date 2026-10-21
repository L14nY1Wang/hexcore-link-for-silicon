import CLiana
import Foundation

// CLI probe: verifies the C bridge against real hardware without launching the
// UI. Run with: swift run LianaProbe

func cString<T>(_ tuple: T, capacity: Int) -> String {
    var value = tuple
    return withUnsafePointer(to: &value) {
        $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
    }
}

if liana_init() != 0 {
    print("hid_init failed")
    exit(1)
}

var devices = [liana_device_info](repeating: liana_device_info(), count: 256)
let count = devices.withUnsafeMutableBufferPointer { liana_enumerate($0.baseAddress, Int32($0.count)) }
print("found \(count) HID devices")
for d in devices.prefix(Int(count)) {
    print("- \(cString(d.product, capacity: Int(LIANA_STRING_MAX))) \(String(format: "%04X:%04X", d.vendor_id, d.product_id)) usb=\(d.is_usb != 0) usage=\(d.usage_page)/\(d.usage) path=\(cString(d.path, capacity: Int(LIANA_PATH_MAX)))")
}

print("permission:", liana_check_listen_access())
for d in devices.prefix(Int(count)) where d.vendor_id == 0x3311 {
    print("anne candidate: product=\(cString(d.product, capacity: Int(LIANA_STRING_MAX))) iface=\(d.interface_number) usage=\(d.usage_page)/\(d.usage)")
}
guard let target = devices.prefix(Int(count)).first(where: {
    $0.vendor_id == 0x3311 && $0.interface_number == 1
}) else {
    print("no keyboard candidate with interface 1")
    exit(0)
}

let name = cString(target.product, capacity: Int(LIANA_STRING_MAX))
print("\nopening \(name)")
guard let handle = liana_open(cString(target.path, capacity: Int(LIANA_PATH_MAX)), Int32(target.is_usb), Int32(target.vendor_id)) else {
    print("open failed")
    exit(1)
}
defer { liana_close(handle) }

func query(_ command: String) -> [UInt8]? {
    var reply = [UInt8](repeating: 0, count: 64)
    let n = reply.withUnsafeMutableBufferPointer {
        liana_transact(handle, command, nil, 0, 3, $0.baseAddress, $0.count, 1500)
    }
    guard n > 0 else { return nil }
    return Array(reply.prefix(Int(n)))
}

for command in ["readFirmwareVersion", "readBatteryPercentage", "readPowerOnTime", "readDeviceType"] {
    if let data = query(command) {
        print("\(command): \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
    } else {
        print("\(command): no reply")
    }
}
