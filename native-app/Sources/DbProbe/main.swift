import Foundation

let dbPath = (NSHomeDirectory() as NSString)
    .appendingPathComponent("Library/Application Support/hexcore-link/hexcore-link.db")

guard let db = VendorDatabase(path: dbPath) else {
    print("cannot open database at \(dbPath): \(VendorDatabase.lastOpenError)")
    exit(1)
}

let tables = db.tableNames()
let common = db.commonValues()
print("tables: \(tables.count) [\(tables.joined(separator: ", "))]")
print("common rows: \(common.count)")
print("kbd_keymap rows: \(db.keymapCount())")

for model in db.deviceModels() {
    print("kbd_keymap deviceModel \(model): \(db.keymaps(deviceModel: model).count) rows")
}

if let sample = db.keymaps(deviceModel: db.deviceModels().first ?? 2).first {
    print("sample columns: \(sample.keys.sorted())")
    print("sample deviceModel=\(sample["deviceModel"] ?? "?"), name=\(sample["name"] ?? "?")")
}

var keymaps: [Keymap] = []
for model in db.deviceModels() {
    for row in db.keymaps(deviceModel: model) {
        guard let keymap = Keymap.parse(row: row) else {
            print("unparsed row (deviceModel \(model)): \(row["id"] ?? "?")")
            continue
        }
        keymaps.append(keymap)
    }
}

print("parsed keymaps: \(keymaps.count)")
for keymap in keymaps {
    print(String(format: "  model %2d %-28s top=%d fn1=%d fn2=%d tap=%d default=%@",
                 keymap.deviceModel, (keymap.name as NSString).utf8String!,
                 keymap.top.count, keymap.fn1.count, keymap.fn2.count, keymap.tap.count,
                 keymap.isDefault ? "y" : "n"))
}

if let sample = keymaps.first {
    print("sample: \(sample.name) id=\(sample.id) deviceModel=\(sample.deviceModel)")
    for (i, key) in sample.top.prefix(6).enumerated() {
        print("  top[\(i)] raw=\(key.raw) -> \(key)")
    }
}

let allKeys = keymaps.flatMap { $0.top + $0.fn1 + $0.fn2 + $0.tap }
let unknown = allKeys.filter { if case .unknown = $0 { return true } else { return false } }
let roundTrip = allKeys.allSatisfy { Keycode(raw: $0.raw) == $0 }
print("decoded keys: \(allKeys.count), unknown: \(unknown.count), round-trip: \(roundTrip)")
if !unknown.isEmpty {
    print("unknown raws: \(Set(unknown.map(\.raw)).sorted().map { String($0, radix: 16) })")
}

if !db.lastError.isEmpty { print("lastError: \(db.lastError)") }
