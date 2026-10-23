import XCTest
@testable import Reader

final class ReaderTests: XCTestCase {
    func testServerAddressIsUserConfiguredAndKeepsReverseProxyPath() throws {
        let url = try ServerConnection.validateURL(" https://reader.example.com:8955/books/reader3/ ")
        XCTAssertEqual(url.absoluteString, "https://reader.example.com:8955/books")
        XCTAssertThrowsError(try ServerConnection.validateURL("https://user:secret@example.com"))
        XCTAssertThrowsError(try ServerConnection.validateURL("file:///etc/passwd"))
        XCTAssertThrowsError(try ServerConnection.validateURL("reader.example.com"))
        XCTAssertEqual(try ServerConnection.validateURL("http://192.168.1.2:8080").scheme, "http")
    }
    func testProgressUsesWebReadersScale() {
        XCTAssertEqual(ProgressPosition.encode(0.375), 3750)
        XCTAssertEqual(ProgressPosition.decode(3750), 0.375, accuracy: 0.00001)
        XCTAssertEqual(ProgressPosition.encode(-1), 0)
        XCTAssertEqual(ProgressPosition.encode(2), 10000)
        XCTAssertEqual(ProgressPosition.encode(.nan), 0)
    }
    func testPlainTextKeepsParagraphsAndDoesNotRunScript() {
        XCTAssertEqual(ReadingTextView.plainText("<p>第一段</p><script>bad()</script><p>第二段&amp;文字</p>"), "第一段\n第二段&文字")
    }
    func testPendingProgressSurvivesNewLibraryAndDoesNotLoseNewerEdits() async throws {
        let identity = "test:" + UUID().uuidString
        let library = LocalLibrary(identity: identity)
        let first = ProgressWrite(bookUrl: "book1", index: 2, position: 4000, expectedUpdatedAt: 100)
        let second = ProgressWrite(bookUrl: "book1", index: 3, position: 2000, expectedUpdatedAt: 100)
        try await library.enqueue(first)
        try await library.enqueue(second)
        try await library.acknowledge(first)
        let restored = LocalLibrary(identity: identity)
        let pending = await restored.pending()
        XCTAssertEqual(pending["book1"], second)
        let otherAccount = LocalLibrary(identity: identity + ":different-account")
        let otherPending = await otherAccount.pending()
        XCTAssertTrue(otherPending.isEmpty)
        try await restored.discardPending(bookURL: "book1")
    }
    func testAPITransmitsRevisionAndAuthHeadersToConfiguredServer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let connection = ServerConnection(baseURL: URL(string: "https://reader.example.com/books")!, username: "reader", accessToken: "test-token", secureKey: "test-key")
        let client = ReaderAPI(connection: connection, session: URLSession(configuration: configuration))
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://reader.example.com/books/reader3/syncBookProgress")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Secure-Key"), "test-key")
            // URLProtocol can expose POST bodies through httpBodyStream instead of httpBody.
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
                }
            }
            let payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(payload["expectedUpdatedAt"] as? Int, 123)
            return Data(#"{"isSuccess":true,"data":{"accepted":false,"book":{"name":"示例","author":"作者","bookUrl":"book1","origin":"source","durChapterIndex":5,"durChapterTime":124}}}"#.utf8)
        }
        let result = try await client.save(ProgressWrite(bookUrl: "book1", index: 2, position: 2500, expectedUpdatedAt: 123))
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.book.chapterIndex, 5)
    }
}

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
