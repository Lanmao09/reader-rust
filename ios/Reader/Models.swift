import Foundation

struct ReaderBook: Codable, Identifiable, Equatable {
    var name: String
    var author: String
    var bookUrl: String
    var origin: String
    var coverUrl: String?
    var durChapterIndex: Int?
    var durChapterPos: Int?
    var durChapterTime: Int64?
    var durChapterTitle: String?
    var totalChapterNum: Int?
    var id: String { bookUrl }
    var revision: Int64 { durChapterTime ?? 0 }
    var chapterIndex: Int { max(0, durChapterIndex ?? 0) }
    var fraction: Double { ProgressPosition.decode(durChapterPos ?? 0) }
}

struct ReaderChapter: Codable, Identifiable, Equatable {
    let title: String
    let url: String
    let index: Int
    var id: String { url }
}

enum ProgressPosition {
    static func encode(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((min(1, max(0, fraction)) * 10_000).rounded())
    }
    // reader-rust's web reader uses a 0...10000 chapter fraction, not pixels.
    static func decode(_ position: Int) -> Double {
        min(1, max(0, position > 1 ? Double(position) / 10_000 : Double(position)))
    }
}

struct ProgressWrite: Codable, Equatable {
    let bookUrl: String
    let index: Int
    let position: Int
    var expectedUpdatedAt: Int64
}

struct ProgressResult: Decodable {
    let accepted: Bool
    let book: ReaderBook
}

struct ServerConnection {
    let baseURL: URL
    let username: String
    var accessToken: String
    let secureKey: String

    static func validateURL(_ raw: String) throws -> URL {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host != nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw ReaderError.invalidAddress }
        // Accept the address users copy from the web reader's API documentation.
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path.hasSuffix("/reader3") { parts.path.removeLast(8) }
        guard let url = parts.url else { throw ReaderError.invalidAddress }
        return url
    }

    var cacheIdentity: String { baseURL.absoluteString + "\n" + username }
}

enum ReaderError: LocalizedError {
    case invalidAddress, invalidResponse, notConnected, loginRequired, server(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "请输入完整服务器地址，例如 https://reader.example.com；不要在网址中包含账号密码。"
        case .invalidResponse: return "服务器返回了无法识别的数据，请确认地址指向 reader-rust。"
        case .notConnected: return "请先连接你的阅读服务器。"
        case .loginRequired: return "登录已过期，请在连接设置中重新登录。离线缓存仍然保留。"
        case .server(let message): return message
        }
    }
}

struct APIEnvelope<Value: Decodable>: Decodable {
    let isSuccess: Bool
    let errorMsg: String?
    let data: Value?
}

struct AccountInfo: Decodable {
    struct User: Decodable { let username: String; let accessToken: String? }
    let userInfo: User?
    let secure: Bool
    let secureKeyRequired: Bool?
    let adminAuthorized: Bool?
}

struct LoginResult: Decodable { let accessToken: String; let username: String }
