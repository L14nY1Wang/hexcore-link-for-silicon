import Foundation
import CSQLiteMC

/// Read-only access to the vendor's encrypted config database.
/// The file uses SQLite3 Multiple Ciphers (chacha20); the key is applied with
/// `PRAGMA key` before the first read, exactly like the vendor preload does.
final class VendorDatabase {
    // Touch a table so a wrong key fails here instead of mid-UI.
    private static let canary = "SELECT count(*) FROM sqlite_master"

    /// The vendor app stores its database key as a literal in the preload
    /// bundle. Read it from the installed copy instead of committing it here.
    private static func cipherKey() -> String? {
        let apps = [
            "/Applications/Hexcore Link.app",
            NSHomeDirectory() + "/Applications/Hexcore Link.app",
        ]
        for app in apps {
            let asar = app + "/Contents/Resources/app.asar"
            guard let data = FileManager.default.contents(atPath: asar) else { continue }
            let marker = Array("rekey='".utf8)
            let bytes = [UInt8](data)
            guard let range = bytes.firstRange(of: marker) else { continue }
            var key: [UInt8] = []
            var i = range.upperBound
            while i < bytes.count, bytes[i] != 0x27, key.count < 128 {
                key.append(bytes[i])
                i += 1
            }
            if !key.isEmpty, let value = String(bytes: key, encoding: .utf8) { return value }
        }
        return nil
    }

    private var db: OpaquePointer?
    private(set) var lastError = ""

    init?(path: String) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            lastError = String(cString: sqlite3_errmsg(db))
            Self.lastOpenError = lastError
            sqlite3_close(db)
            db = nil
            return nil
        }
        guard let key = Self.cipherKey() else {
            lastError = "vendor app.asar not found; cannot read the database key"
            Self.lastOpenError = lastError
            sqlite3_close(db)
            db = nil
            return nil
        }
        guard exec("PRAGMA key='\(key)'"), exec(Self.canary) else { return nil }
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
