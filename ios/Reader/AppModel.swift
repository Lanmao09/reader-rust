import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var connection: ServerConnection?
    @Published var books: [ReaderBook] = []
    @Published var status = "连接自己的阅读服务器，接着上次的地方读。"
    @Published var error: String?
    @Published var loading = false
    private(set) var library: LocalLibrary?
    var api: ReaderAPI? { connection.map { ReaderAPI(connection: $0) } }

    init() {
        if let saved = Credentials.load(), let url = try? ServerConnection.validateURL(saved.server) {
            let connection = ServerConnection(baseURL: url, username: saved.username, accessToken: saved.token, secureKey: saved.secureKey)
            self.connection = connection
            self.library = LocalLibrary(identity: connection.cacheIdentity)
        }
    }
    func connect(server: String, username: String, password: String, secureKey: String) async throws {
        var next = ServerConnection(baseURL: try ServerConnection.validateURL(server),
                                    username: username.trimmingCharacters(in: .whitespacesAndNewlines), accessToken: "", secureKey: secureKey)
        var client = ReaderAPI(connection: next)
        if !next.username.isEmpty {
            let login = try await client.login(username: next.username, password: password)
            next.accessToken = login.accessToken
            client.connection = next
        }
        let account = try await client.account()
        if account.secure && account.userInfo == nil && account.adminAuthorized != true { throw ReaderError.loginRequired }
        let shelf = try await client.bookshelf()
        try Credentials.save(next)
        connection = next
        library = LocalLibrary(identity: next.cacheIdentity)
        books = shelf
        try await library?.write(shelf, for: "bookshelf")
        await refresh()
    }
    func refresh() async {
        guard let api, let library, !loading else { return }
        loading = true
        defer { loading = false }
        if books.isEmpty { books = await library.read("bookshelf", as: [ReaderBook].self) ?? [] }
        do {
            // Replay only if the server still has the revision this device last saw.
            var conflicts = 0
            for progress in await library.pending().values {
                let result = try await api.save(progress)
                if result.accepted { try await library.acknowledge(progress) } else { conflicts += 1 }
            }
            books = try await api.bookshelf()
            try await library.write(books, for: "bookshelf")
            status = conflicts == 0 ? "进度已同步 · 网页与 App 共用书架" : "有 \(conflicts) 本书的设备进度不同，打开书籍后选择。"
            error = nil
        } catch {
            self.error = error.localizedDescription
            status = "当前显示离线书架；已缓存的章节可继续阅读。"
        }
    }
}
