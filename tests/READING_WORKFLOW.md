# 阅读流程验收范围

测试数量不能代替完整操作链路。本页区分真实后端浏览器测试、受控 API 上的原生 UI 测试和真实设备验收。

## 本轮执行结果（2026-10-23）

| 验收项 | 结果 | 实际覆盖 |
| --- | --- | --- |
| 网页完整阅读流程 | 1 项通过 | 真实 Rust 后端：登录、上传书源 JSON、搜索、加书架、打开正文、翻章、滚动保存；第二个独立登录的移动端浏览器恢复到第二章约 40% 的位置 |
| 网页基础导航 | 5 项通过 | 关闭账号模式的独立测试实例，使用 `app-shell.spec.ts` |
| 前端单元测试 | 79 项通过 | `frontend` 的 Vitest 测试集 |
| Rust 测试 | 131 项通过、1 项忽略 | 包含并发进度写入、过期修订冲突、书架排序保留进度和账号隔离；忽略项为外部在线书源测试 |
| iPhone / iPad 原生 UI | 已停止补测，未通过完整验收 | 按用户要求停止云端模拟器测试；以前失败、取消或未运行的用例不计为通过 |
| 用户 NAS、外部书源、自签真机 | 未验证 | 需要真实部署和设备联调 |

本轮完整流程发现并修复了两个问题：新客户端打开书籍时未等待书籍加载便跳转，可能被阅读页退回书架；原生 App 成功上传进度后，未同步更新离线书架中的位置，直接结束进程后离线重开可能退回旧位置。网页修复已通过完整流程回归；原生修复尚未通过完整 UI 验收。

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

按用户要求，GitHub Actions 的 `Build iOS IPA` 现仅执行真机目标的 Release 编译和未签名 IPA 打包，不再运行云端模拟器测试。历史测试结果以对应运行记录为准；IPA 编译成功不代表原生完整流程、真机或 NAS 验收通过。原生测试源码保留，可在 Mac 本地继续运行。

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
