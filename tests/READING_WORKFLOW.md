# 阅读流程验收范围

测试数量不能代替完整操作链路。本页区分真实后端浏览器测试、受控 API 上的原生 UI 测试和真实设备验收。

## 网页：真实 Rust 后端 + 受控书源网站

`tests/e2e/source-reading-flow.spec.ts` 会创建独立测试账号，通过网页登录、上传书源 JSON、搜索一本书、加入书架、打开正文、翻到下一章并保存位置。随后使用第二个独立登录的浏览器打开同一本书，断言恢复到同一章节。书源 HTML、目录和正文来自 `tests/fixtures/reader_site.py`，内容为自行编写；服务端实际执行 HTTP 抓取和 CSS 规则解析，未 mock `/reader3` API。

运行需要一个专用、可丢弃的本地 reader-rust 实例（`SECURE=true`、独立 `STORAGE_DIR` 和 SQLite 文件）。测试拒绝使用非 loopback 地址，并且只有显式设置 `READER_TEST_SERVER=1` 才会执行，避免写入个人 NAS。

```bash
# 先激活 Rust 工具链，并构建前后端。
cargo build --locked -j 4
(cd frontend && npm ci && npm run build)

# 在另一个终端启动专用实例；存储目录必须使用独立的测试目录。
SERVER_HOST=127.0.0.1 SERVER_PORT=18080 SECURE=true \
STORAGE_DIR=/tmp/reader-e2e ASSETS_DIR=/tmp/reader-e2e/assets \
DATABASE_URL='sqlite:/tmp/reader-e2e/reader.db?mode=rwc' \
./target/debug/reader-rust

# 在仓库根目录执行，Chrome 或指定的系统 Chromium 需要预先安装。
READER_TEST_SERVER=1 PLAYWRIGHT_BASE_URL=http://127.0.0.1:18080 \
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium \
npx playwright test --config playwright.source-flow.config.ts
```

基础页面导航测试 `app-shell.spec.ts` 使用未开启账号模式的专用实例。它与开启账号模式的完整阅读流程分开运行，避免用登录弹窗遮住未登录页面后误判导航功能。

## iPhone / iPad：原生模拟器 UI

`ios/ReaderUITests/ReaderUITests.swift` 使用 XCUITest 实际点击 App：输入服务器和账号、登录、打开书架书籍、调字号及夜读主题、查看目录、翻章、缓存、强制结束进程后离线打开、离线翻章后再次重启、恢复联网同步、接续另一设备的位置，以及处理同步冲突。

这里使用受控的 `/reader3` API fixture，**不能把它描述为已经连接真实 NAS 或真实公开书源**。断网测试通过让 fixture 对所有阅读 API 返回 503 完成，并强制终止、重新启动 App 验证持久化，而不是仅检查内存状态。

GitHub Actions 的 `Build iOS IPA` 会分别在 iPhone 和 iPad 模拟器运行原生单元测试与 UI 测试。每个任务要求至少 7 项测试通过后才通过校验，测试结果和截图保存在 `iOS-test-results-iPhone` / `iOS-test-results-iPad` 产物中。以对应工作流的实际结果为准；排队、未运行或失败不能视为通过。

Mac 手动运行：先启动 fixture，再在 Xcode 中对 `Reader` scheme 执行 Test。

```bash
python3 tests/fixtures/reader_site.py --mobile-api --port 18998
python3 ios/generate_project.py
open ios/Reader.xcodeproj
```

## 未由上述测试证明的事项

- 用户 NAS 上当前部署的版本、网络和账号配置。
- 用户实际使用的外部书源，包括登录、验证码、反爬、收费或第三方网站变更。
- 自签安装、证书有效期、iPhone / iPad 真机上的手势和长时间阅读体验。
- 所有辅助功能，例如 RSS、朗读、漫画等。

当前原生 App 仍通过网页管理书源和搜索加书，不能把网页测试记作“IPA 内导入书源已测试”。
