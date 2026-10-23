import XCTest

final class ReaderUITests: XCTestCase {
    private enum FlowError: Error { case assertion(String) }
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
    private func fill(_ field: XCUIElement, with value: String) async throws {
        field.tap()
        if let current = field.value as? String, current != field.placeholderValue {
            if !current.isEmpty {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
        }
        // Give SwiftUI and the simulator keyboard time to commit each keystroke.
        // Sending a complete string at once can lose characters on a busy runner.
        for character in value { field.typeText(String(character)) }
        try await wait(NSPredicate(format: "value == %@", value), on: field,
                       message: "字段输入不匹配：\(field.identifier)，实际值：\(String(describing: field.value))", timeout: 10)
    }

    @MainActor
    private func require(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else {
            XCTFail(message, file: file, line: line)
            throw FlowError.assertion(message)
        }
    }

    @MainActor
    private func visibleText(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    @MainActor
    private func wait(_ predicate: NSPredicate, on element: XCUIElement, message: @autoclosure () -> String, timeout: TimeInterval = 20) async throws {
        let result = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        if result != .completed {
            try require(false, message() + " (wait result: \(result.rawValue))")
        }
    }

    @MainActor
    private func openBook(_ app: XCUIApplication) throws {
        let book = app.buttons["book:" + server.absoluteString + "/book/1"]
        try require(book.waitForExistence(timeout: 20), "书架未出现：" + visibleText(app))
        book.tap()
        try require(app.textViews["reader.body"].waitForExistence(timeout: 20), "正文未出现：" + visibleText(app))
    }

    @MainActor
    private func expectChapter(_ number: Int, app: XCUIApplication) async throws {
        let predicate = NSPredicate(format: "value CONTAINS %@", "第\(number)章正文")
        try await wait(predicate, on: app.textViews["reader.body"], message: "未打开第\(number)章：" + visibleText(app))
    }

    @MainActor
    private func enterPasswordWithKeyboard(_ app: XCUIApplication) throws {
        app.secureTextFields["connection.password"].tap()
        let keyboard = app.keyboards.firstMatch
        try require(keyboard.waitForExistence(timeout: 20), "屏幕键盘没有出现")
        for character in "e2epassword" {
            let key = keyboard.keys[String(character)]
            if !key.exists {
                let toggle = keyboard.keys.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "more", ["123", "ABC", "Numbers", "Letters"] as NSArray)).firstMatch
                try require(toggle.waitForExistence(timeout: 5), "键盘没有字母/数字切换键：" + keyboard.debugDescription)
                toggle.tap()
            }
            try require(key.waitForExistence(timeout: 5), "键盘没有测试所需的按键：\(character)")
            key.tap()
        }
    }

    @MainActor
    func testLoginReadSettingsOfflineRestartAndProgressHandoff() async throws {
        continueAfterFailure = false
        _ = try await fixture("__control", body: ["offline": false, "index": 0, "position": 0])
        let app = XCUIApplication()
        app.launchEnvironment["READER_UI_DIAGNOSTICS"] = "1"
        app.launch()
        app.buttons["服务器与账号"].tap()
        try await fill(app.textFields["connection.server"], with: server.absoluteString)
        try await fill(app.textFields["connection.username"], with: "e2ereader")
        try enterPasswordWithKeyboard(app)
        let connect = app.buttons["连接并同步书架"]
        if !connect.isHittable { app.swipeUp() }
        connect.tap()
        let loginDeadline = Date().addingTimeInterval(20)
        var receivedLogin: [String: Any]?
        while receivedLogin == nil && Date() < loginDeadline {
            let observed = try await fixture("__state")
            receivedLogin = observed["lastLogin"] as? [String: Any]
            if receivedLogin == nil { try await Task.sleep(nanoseconds: 200_000_000) }
        }
        let credentialsArrived = receivedLogin?["usernameMatches"] as? Bool == true && receivedLogin?["passwordMatches"] as? Bool == true
        try require(credentialsArrived, "测试服务未收到完整的登录凭证（仅记录匹配结果和长度）：\(receivedLogin ?? [:])")
        try await wait(NSPredicate(format: "exists == false"), on: app.navigationBars["服务器与账号"], message: "连接失败：" + visibleText(app), timeout: 60)
        try openBook(app)
        try await expectChapter(1, app: app)

        app.buttons["阅读设置"].tap()
        app.sliders["reading.fontSize"].adjust(toNormalizedSliderPosition: 0.65)
        app.buttons["夜读"].tap()
        try require(app.buttons["夜读"].isSelected, "夜读主题未选中")
        app.buttons["完成"].tap()
        app.buttons["下一章"].tap()
        try await expectChapter(2, app: app)
        app.buttons["目录"].tap()
        try require(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第3章 测试章节")).firstMatch.waitForExistence(timeout: 5), "目录未列出第三章")
        app.buttons["完成"].tap()

        app.buttons["缓存接下来三十章"].tap()
        try await wait(NSPredicate(format: "label CONTAINS %@", "已缓存接下来的"), on: app.staticTexts["reader.syncStatus"], message: "缓存未完成")
        let reading = XCTAttachment(screenshot: app.screenshot())
        reading.name = "Native reader after changing font and paper theme"
        reading.lifetime = .keepAlways
        add(reading)
        _ = try await fixture("__control", body: ["offline": true])
        app.terminate()
        app.launch()
        try openBook(app)
        try await expectChapter(2, app: app)
        app.buttons["下一章"].tap()
        try await expectChapter(3, app: app)
        app.terminate()
        app.launch()
        try openBook(app)
        try await expectChapter(3, app: app)

        _ = try await fixture("__control", body: ["offline": false])
        XCUIDevice.shared.press(.home)
        app.activate()
        try await wait(NSPredicate(format: "label == %@", "已同步到网页"), on: app.staticTexts["reader.syncStatus"], message: "离线进度未回传")
        let state = try await fixture("__state")
        try require((state["book"] as? [String: Any])?["durChapterIndex"] as? Int == 2, "服务器没有收到第三章进度：\(state)")

        XCUIDevice.shared.press(.home)
        _ = try await fixture("__control", body: ["index": 3, "position": 5000])
        app.activate()
        try await expectChapter(4, app: app)
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "50%")).firstMatch.waitForExistence(timeout: 10), "未恢复章内 50% 位置")
        app.textViews["reader.body"].swipeUp()
        try await wait(NSPredicate(format: "label == %@", "已同步到网页"), on: app.staticTexts["reader.syncStatus"], message: "滚动后未同步")
        let scrolled = try await fixture("__state")
        try require(((scrolled["book"] as? [String: Any])?["durChapterPos"] as? Int ?? 0) > 5000, "滚动后服务器位置未前进：\(scrolled)")
        _ = try await fixture("__control", body: ["index": 5, "position": 3000])
        app.buttons["上一章"].tap()
        let resume = app.buttons["接着另一设备读"]
        try require(resume.waitForExistence(timeout: 20), "未提示另一设备的进度冲突")
        resume.tap()
        try await expectChapter(6, app: app)
    }
}
