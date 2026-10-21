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

var layerBuf = [UInt8](repeating: 0, count: 2048)
var request: [UInt8] = [0]
let layerLen: Int32 = layerBuf.withUnsafeMutableBufferPointer { out in
    request.withUnsafeBufferPointer { req in
        liana_read_command_payload(handle, "readKeyboardLayer", 3, req.baseAddress, 1,
                                   out.baseAddress, out.count, 2000)
    }
}
print("readKeyboardLayer(0): \(layerLen)")

if layerLen > 1 {
    var keys: [UInt16] = []
    for i in stride(from: 0, to: Int(layerLen) - 1, by: 2) {
        keys.append(UInt16(layerBuf[i]) | (UInt16(layerBuf[i + 1]) << 8))
    }
    // Round-trip: write the exact bytes back, then read again.
    var payload: [UInt8] = [0]
    for key in keys { payload.append(UInt8(key & 0xff)); payload.append(UInt8(key >> 8)) }
    let rc = payload.withUnsafeBufferPointer {
        liana_write(handle, "writeKeyboardLayer", $0.baseAddress, payload.count, 3)
    }
    usleep(300_000)
    var verify = [UInt8](repeating: 0, count: 2048)
    let verifyLen: Int32 = verify.withUnsafeMutableBufferPointer { out in
        var req: [UInt8] = [0]
        return req.withUnsafeBufferPointer { r in
            liana_read_command_payload(handle, "readKeyboardLayer", 3, r.baseAddress, 1,
                                       out.baseAddress, out.count, 2000)
        }
    }
    print("write rc=\(rc) verifyLen=\(verifyLen) identical=\(verifyLen == layerLen && verify[0..<Int(layerLen)].elementsEqual(layerBuf[0..<Int(layerLen)]))")
}
if layerLen > 0 {
    var keys: [UInt16] = []
    for i in stride(from: 0, to: Int(layerLen) - 1, by: 2) {
        keys.append(UInt16(layerBuf[i]) | (UInt16(layerBuf[i + 1]) << 8))
    }
    print("keyboardLayer(0): \(layerLen) bytes, \(keys.count) keys, first: \(keys.prefix(8).map { String(format: "%04x", $0) })")
} else {
    print("keyboardLayer(0): no reply")
}

for command in ["readFirmwareVersion", "readBatteryPercentage", "readPowerOnTime", "readDeviceType"] {
    if let data = query(command) {
        print("\(command): \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
    } else {
        print("\(command): no reply")
    }
}
