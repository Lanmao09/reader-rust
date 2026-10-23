import XCTest

final class ReaderUITests: XCTestCase {
    // This address belongs only to the disposable test fixture, never to the app.
    private let server = URL(string: "http://127.0.0.1:18998")!

    private func fixture(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: server.appendingPathComponent(path))
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @MainActor
    private func fill(_ field: XCUIElement, with value: String) {
        field.tap()
        if let current = field.value as? String, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value)
    }

    @MainActor
    private func openBook(_ app: XCUIApplication) {
        let book = app.buttons["book:" + server.absoluteString + "/book/1"]
        XCTAssertTrue(book.waitForExistence(timeout: 20), "书架未出现：" + app.debugDescription.replacingOccurrences(of: "\n", with: " | "))
        book.tap()
        XCTAssertTrue(app.textViews["reader.body"].waitForExistence(timeout: 20))
    }

    @MainActor
    private func expectChapter(_ number: Int, app: XCUIApplication) {
        let predicate = NSPredicate(format: "value CONTAINS %@", "第\(number)章正文")
        expectation(for: predicate, evaluatedWith: app.textViews["reader.body"])
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testLoginReadSettingsOfflineRestartAndProgressHandoff() async throws {
        continueAfterFailure = false
        _ = try await fixture("__control", body: ["offline": false, "index": 0, "position": 0])
        let app = XCUIApplication()
        app.launch()
        app.buttons["服务器与账号"].tap()
        fill(app.textFields["connection.server"], with: server.absoluteString)
        fill(app.textFields["connection.username"], with: "e2ereader")
        app.secureTextFields["connection.password"].tap()
        app.secureTextFields["connection.password"].typeText("e2epassword")
        let connect = app.buttons["连接并同步书架"]
        if !connect.isHittable { app.swipeUp() }
        connect.tap()
        openBook(app)
        expectChapter(1, app: app)

        app.buttons["阅读设置"].tap()
        app.sliders["reading.fontSize"].adjust(toNormalizedSliderPosition: 0.65)
        app.buttons["夜读"].tap()
        XCTAssertTrue(app.buttons["夜读"].isSelected)
        app.buttons["完成"].tap()
        app.buttons["下一章"].tap()
        expectChapter(2, app: app)
        app.buttons["目录"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第3章 测试章节")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        app.buttons["缓存接下来三十章"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "已缓存接下来的"), evaluatedWith: app.staticTexts["reader.syncStatus"])
        waitForExpectations(timeout: 20)
        let reading = XCTAttachment(screenshot: app.screenshot())
        reading.name = "Native reader after changing font and paper theme"
        reading.lifetime = .keepAlways
        add(reading)
        _ = try await fixture("__control", body: ["offline": true])
        app.terminate()
        app.launch()
        openBook(app)
        expectChapter(2, app: app)
        app.buttons["下一章"].tap()
        expectChapter(3, app: app)
        app.terminate()
        app.launch()
        openBook(app)
        expectChapter(3, app: app)

        _ = try await fixture("__control", body: ["offline": false])
        XCUIDevice.shared.press(.home)
        app.activate()
        expectation(for: NSPredicate(format: "label == %@", "已同步到网页"), evaluatedWith: app.staticTexts["reader.syncStatus"])
        waitForExpectations(timeout: 20)
        let state = try await fixture("__state")
        XCTAssertEqual((state["book"] as? [String: Any])?["durChapterIndex"] as? Int, 2)

        XCUIDevice.shared.press(.home)
        _ = try await fixture("__control", body: ["index": 3, "position": 5000])
        app.activate()
        expectChapter(4, app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "50%")).firstMatch.waitForExistence(timeout: 10))
        app.textViews["reader.body"].swipeUp()
        expectation(for: NSPredicate(format: "label == %@", "已同步到网页"), evaluatedWith: app.staticTexts["reader.syncStatus"])
        waitForExpectations(timeout: 20)
        let scrolled = try await fixture("__state")
        XCTAssertGreaterThan((scrolled["book"] as? [String: Any])?["durChapterPos"] as? Int ?? 0, 5000)
        _ = try await fixture("__control", body: ["index": 5, "position": 3000])
        app.buttons["上一章"].tap()
        let resume = app.buttons["接着另一设备读"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        resume.tap()
        expectChapter(6, app: app)
    }
}
