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

for model in db.deviceModels() {
    guard let row = db.keymaps(deviceModel: model).first else { continue }
    for col in ["top", "fn1", "fn2", "tap", "macro"] {
        let s = String(describing: row[col] ?? "nil")
        print("[\(model)] \(col) (\(s.count)): \(s.prefix(300))")
    }
    break
}
if !db.lastError.isEmpty { print("lastError: \(db.lastError)") }
