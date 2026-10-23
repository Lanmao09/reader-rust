import Foundation
import CryptoKit

/// Every server/account has its own cache and durable upload queue.
actor LocalLibrary {
    private let root: URL
    init(identity: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Reader/" + Self.digest(identity), isDirectory: true)
    }
    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func file(_ key: String) -> URL { root.appendingPathComponent(Self.digest(key) + ".json") }
    func read<Value: Decodable>(_ key: String, as type: Value.Type) -> Value? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func write<Value: Encodable>(_ value: Value, for key: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var excluded = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }
    func pending() -> [String: ProgressWrite] { read("pending", as: [String: ProgressWrite].self) ?? [:] }
    func enqueue(_ progress: ProgressWrite) throws {
        var all = pending()
        all[progress.bookUrl] = progress
        try write(all, for: "pending")
    }
    func acknowledge(_ progress: ProgressWrite) throws {
        var all = pending()
        if all[progress.bookUrl] == progress { all.removeValue(forKey: progress.bookUrl) }
        try write(all, for: "pending")
    }
    func discardPending(bookURL: String) throws {
        var all = pending()
        all.removeValue(forKey: bookURL)
        try write(all, for: "pending")
    }
}
