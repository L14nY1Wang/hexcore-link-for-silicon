import Foundation
import CSQLiteMC

/// Read-only access to the vendor's encrypted config database.
/// The file uses SQLite3 Multiple Ciphers (chacha20); the key is applied with
/// `PRAGMA key` before the first read, exactly like the vendor preload does.
final class VendorDatabase {
    // The vendor preload embeds this key as a literal; keep the native app
    // self-contained instead of requiring a local Electron installation.
        // Stored XOR-obfuscated so the key is not a verbatim string in the
    // binary. This is obfuscation, not a security boundary.
    private static let cipherKey: String = {
        guard let data = Data(base64Encoded: "KT85KD8uBTE/IwVqYmxqb2tob2lvY2hqa2I=") else { return "" }
        return String(bytes: data.map { $0 ^ 0x5A }, encoding: .utf8) ?? ""
    }()

    // Touch a table so a wrong key fails here instead of mid-UI.
    private static let canary = "SELECT count(*) FROM sqlite_master"

    private var db: OpaquePointer?
    private(set) var lastError = ""

    init?(path: String) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            lastError = String(cString: sqlite3_errmsg(db))
            Self.lastOpenError = lastError
            sqlite3_close(db)
            db = nil
            return nil
        }
        sqlite3_busy_timeout(db, 3000)
        guard exec("PRAGMA key='\(Self.cipherKey)'"), exec(Self.canary) else { return nil }
    }

    /// Persist an edited keymap. The vendor stores each layer as a JSON array
    /// of raw keycode numbers.
    func updateKeymap(id: Int, top: [Int], fn1: [Int], fn2: [Int], tap: [Int]) -> Bool {
        let sql = "UPDATE kbd_keymap SET top = ?, fn1 = ?, fn2 = ?, tap = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = String(cString: sqlite3_errmsg(db))
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let json = { (values: [Int]) in "[" + values.map(String.init).joined(separator: ",") + "]" }
        sqlite3_bind_text(stmt, 1, json(top), -1, transient)
        sqlite3_bind_text(stmt, 2, json(fn1), -1, transient)
        sqlite3_bind_text(stmt, 3, json(fn2), -1, transient)
        sqlite3_bind_text(stmt, 4, json(tap), -1, transient)
        sqlite3_bind_int64(stmt, 5, Int64(id))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            lastError = String(cString: sqlite3_errmsg(db))
            return false
        }
        return true
    }

    deinit { sqlite3_close(db) }

    func tableNames() -> [String] {
        rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            .compactMap { $0["name"] as? String }
    }

    func commonValues() -> [String: String] {
        var values: [String: String] = [:]
        for row in rows("SELECT key, value FROM common") {
            if let key = row["key"] as? String, let value = row["value"] as? String {
                values[key] = value
            }
        }
        return values
    }

    func keymaps(deviceModel: Int) -> [[String: Any]] {
        rows("SELECT * FROM kbd_keymap WHERE deviceModel = \(deviceModel) ORDER BY rowid")
    }

    func keymapCount() -> Int {
        (rows("SELECT count(*) AS n FROM kbd_keymap").first?["n"] as? Int64).map(Int.init) ?? 0
    }

    static var lastOpenError = ""

    func deviceModels() -> [Int] {
        rows("SELECT DISTINCT deviceModel FROM kbd_keymap ORDER BY deviceModel")
            .compactMap { ($0["deviceModel"] as? Int64).map(Int.init) }
    }

    // MARK: - SQLite plumbing

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            lastError = String(cString: sqlite3_errmsg(db))
            return false
        }
        return true
    }

    private func rows(_ sql: String) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = String(cString: sqlite3_errmsg(db))
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var result: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for column in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, column))
                row[name] = value(stmt, column)
            }
            result.append(row)
        }
        return result
    }

    private func value(_ stmt: OpaquePointer?, _ column: Int32) -> Any {
        switch sqlite3_column_type(stmt, column) {
        case SQLITE_INTEGER: return sqlite3_column_int64(stmt, column)
        case SQLITE_FLOAT: return sqlite3_column_double(stmt, column)
        case SQLITE_TEXT: return String(cString: sqlite3_column_text(stmt, column))
        case SQLITE_BLOB:
            let count = sqlite3_column_bytes(stmt, column)
            guard let bytes = sqlite3_column_blob(stmt, column), count > 0 else { return Data() }
            return Data(bytes: bytes, count: Int(count))
        default: return NSNull()
        }
    }
}
