import Foundation
import Security

enum Credentials {
    private static let service = "org.reader-rust.native.credentials"
    struct Saved: Codable {
        let server: String
        let username: String
        let token: String
        let secureKey: String
    }
    static func load() -> Saved? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "connection",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }
    static func save(_ connection: ServerConnection) throws {
        let value = Saved(server: connection.baseURL.absoluteString, username: connection.username,
                          token: connection.accessToken, secureKey: connection.secureKey)
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ReaderError.server("无法安全保存登录信息（\(status)）") }
    }
}
