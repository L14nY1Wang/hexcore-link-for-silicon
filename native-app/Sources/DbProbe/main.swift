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

// Round-trip one keymap through updateKeymap (same values) to exercise the
// write path without changing the user's data.
if let database = VendorDatabase(path: NSHomeDirectory() + "/Library/Application Support/hexcore-link/hexcore-link.db"),
   let row = database.keymaps(deviceModel: 2).first(where: { ($0["name"] as? String) == "intl.keymap.qwerty" }),
   let keymap = Keymap.parse(row: row) {
    let ok = database.updateKeymap(
        id: keymap.id,
        top: keymap.top.map(\.raw),
        fn1: keymap.fn1.map(\.raw),
        fn2: keymap.fn2.map(\.raw),
        tap: keymap.tap.map(\.raw)
    )
    let reloaded = database.keymaps(deviceModel: 2).first { ($0["id"] as? Int64) == Int64(keymap.id) }
    let parsed = reloaded.flatMap(Keymap.parse(row:))
    print("updateKeymap ok=\(ok) identical=\(parsed?.top == keymap.top && parsed?.fn1 == keymap.fn1 && parsed?.fn2 == keymap.fn2 && parsed?.tap == keymap.tap)")
}


if let table = ProcessInfo.processInfo.environment["DBPROBE_TABLE"] {
    print("--- \(table) schema ---")
    for col in db.query("PRAGMA table_info(\(table))") {
        print("  \(col["name"] ?? "?") \(col["type"] ?? "?")")
    }
    print("--- rows ---")
    for row in db.query("SELECT * FROM \(table) LIMIT 30") {
        let text = row.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " | ")
        print(text.prefix(600))
    }
}


if let sql = ProcessInfo.processInfo.environment["DBPROBE_SQL"] {
    for row in db.query(sql) {
        print(row.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " | "))
    }
}
