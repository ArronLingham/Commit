import Foundation

/// The pairing code that ties two devices to the same synced "space".
/// Stored in shared defaults. There is intentionally no login — knowing the code
/// grants access (acceptable for a personal app; the code is long and unguessable).
public enum SyncCode {
    private static let key = "syncCode"

    public static var current: String? {
        let value = CommitConstants.sharedDefaults.string(forKey: key)
        return (value?.isEmpty == false) ? value : nil
    }

    public static func set(_ code: String?) {
        let defaults = CommitConstants.sharedDefaults
        if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(normalize(code), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// A friendly, unambiguous code like `AB3F-7KMN-PQ24-RST9`.
    public static func generate() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no 0/O/1/I
        func group() -> String { String((0..<4).map { _ in alphabet.randomElement()! }) }
        return "\(group())-\(group())-\(group())-\(group())"
    }

    /// Uppercase + trim so the same code typed slightly differently still matches.
    public static func normalize(_ code: String) -> String {
        code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
