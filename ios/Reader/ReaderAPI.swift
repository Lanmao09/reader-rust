import Foundation

struct ReaderAPI {
    var connection: ServerConnection
    var session: URLSession = .shared

    func request<Value: Decodable>(_ route: String, body: [String: Any]? = nil) async throws -> Value {
        var request = URLRequest(url: connection.baseURL.appendingPathComponent("reader3/" + route))
        request.timeoutInterval = 45
        if !connection.accessToken.isEmpty { request.setValue(connection.accessToken, forHTTPHeaderField: "Authorization") }
        if !connection.secureKey.isEmpty { request.setValue(connection.secureKey, forHTTPHeaderField: "X-Secure-Key") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReaderError.invalidResponse }
        if response.statusCode == 401 { throw ReaderError.loginRequired }
        guard let envelope = try? JSONDecoder().decode(APIEnvelope<Value>.self, from: data) else {
            if response.statusCode == 404, route == "syncBookProgress" {
                throw ReaderError.server("服务器尚未更新到支持进度同步的版本，请先部署本分支的 reader-rust 后端。")
            }
            throw ReaderError.invalidResponse
        }
        if !envelope.isSuccess {
            if envelope.errorMsg == "NEED_LOGIN" { throw ReaderError.loginRequired }
            throw ReaderError.server(envelope.errorMsg ?? "请求失败")
        }
        guard (200..<300).contains(response.statusCode), let value = envelope.data else { throw ReaderError.invalidResponse }
        return value
    }

    func account() async throws -> AccountInfo { try await request("getUserInfo") }
    func login(username: String, password: String) async throws -> LoginResult {
        try await request("login", body: ["username": username, "password": password, "isLogin": true])
    }
    func bookshelf() async throws -> [ReaderBook] { try await request("getBookshelf") }
    func book(_ url: String) async throws -> ReaderBook { try await request("getShelfBook", body: ["url": url]) }
    func chapters(_ book: ReaderBook) async throws -> [ReaderChapter] {
        try await request("getChapterList", body: ["bookUrl": book.bookUrl, "bookSourceUrl": book.origin])
    }
    func content(_ chapter: ReaderChapter, book: ReaderBook) async throws -> String {
        try await request("getBookContent", body: ["chapterUrl": chapter.url, "bookSourceUrl": book.origin, "index": chapter.index])
    }
    func save(_ progress: ProgressWrite) async throws -> ProgressResult {
        try await request("syncBookProgress", body: [
            "bookUrl": progress.bookUrl, "index": progress.index, "position": progress.position,
            "expectedUpdatedAt": progress.expectedUpdatedAt,
        ])
    }
}
