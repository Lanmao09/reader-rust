# 阅间 · reader-rust 原生 iOS 客户端

面向 iPhone 和 iPad（iOS / iPadOS 16 及以上）。电脑继续使用现有网页，App 使用同一服务器、同一账号、同一本书的书架记录。服务器地址在登录页输入，支持域名、端口、局域网 HTTP、HTTPS 反代和反代子路径；没有内置私人地址。

## 第一版功能

- 原生 SwiftUI 书架和 UIKit 文字排版，不通过 WebView 包装网页。
- 上下滑动阅读、点按左右边缘翻一屏、目录跳转；点击中间区域隐藏工具栏。
- 字号、行距、宋体 / 系统字体、四种纸张主题、亮度和常亮设置。适配横屏及 iPad 正文宽度。
- 自动缓存接下来的三章，也可缓存接下来的三十章；已缓存目录和章节可以离线阅读。
- 联网时读取云端进度；滚动停止后自动保存，切到后台时尝试完成上传。离线进度先持久化在本机，重新连接后重传。
- 同步使用服务端版本检查。另一设备已更新时，明确选择“接着另一设备读”或“保留本机位置”，允许回看旧章节，不用“章节数最大”代替最新进度。
- 登录凭证和安全密钥保存到 iOS Keychain，不保存登录密码；缓存按服务器和账号隔离。

当前以文字小说为主；没有复刻参考 IPA 的漫画、外部书源管理、朗读、书籍插图、仿真翻页或全部设置。书籍和书源可在现有网页管理。本项目没有复用或嵌入上传 IPA 的二进制、图标、私有数据或未提供的源码。

## 服务器需要更新

App 使用本分支新增的 `POST /reader3/syncBookProgress`。**NAS 上的旧后端和旧网页需要一并更新**，仅安装 IPA 无法获得新的冲突保护。旧的 `saveBookProgress` 仍然兼容，但旧网页没有版本检查，应刷新到新前端。

新接口请求：

```json
{"bookUrl":"书架中的 bookUrl","index":8,"position":3750,"expectedUpdatedAt":1234567890}
```

`position` 使用现有网页的 0…10000 章节内相对位置，`expectedUpdatedAt` 原样使用上次读取的 `durChapterTime`，不要转换单位或用客户端时钟替代。响应为 `{"isSuccess":true,"data":{"accepted":true,"book":{...}}}`。冲突时 `accepted` 为 `false`，`book` 是当前云端记录；不会写入。客户端可以让用户选择后使用返回的版本再次提交。

章节和章节内相对位置可跨设备接续；因屏幕尺寸和排版不同，不保证逐字定位。没有声称未下载的书可以离线读取，也不能在离线时获取另一设备的进度。

## 获取可自签 IPA

GitHub Actions 工作流为 **Build iOS IPA**（`.github/workflows/ios.yml`）。推送修改 `ios/` 的分支会自动触发；合入默认分支后，也可在 Actions 页面手动 Run workflow。

1. 打开对应工作流运行，等待 Release 构建成功。按用户要求，云端工作流仅构建 IPA，不再运行模拟器测试。
2. 在该次运行的 Artifacts 中下载 **Reader-unsigned-IPA**，解开外层 ZIP，得到 `Reader-unsigned.ipa`。
3. 使用自己的 Apple ID / 签名证书，通过支持自签的安装工具签名后安装。此文件未经签名，不能直接点开安装，也不是 TestFlight 分发包。签名有效期取决于使用的账号和工具。
4. App 中填写服务器地址，再用与电脑网页相同的账号登录。未开启账号模式的服务器可以留空账号。

工作流只需要仓库 `contents: read`，不要求上传 Apple 密码或签名证书到 GitHub。构建产物保留 14 天。首次从 fork 运行 Actions 可能需要仓库所有者在 GitHub 中启用 Actions；额度和 macOS runner 可用性由 GitHub 账号决定。

仓库 Releases 也可保存 IPA 和 SHA-256 校验文件。未经完整真机和 NAS 联调的版本应标记为预发布；草稿 Release 仅有写权限的仓库成员可见，发布后的下载权限由仓库可见性决定。

HTTP 适用于自己控制的局域网；公网反代请使用系统信任的 HTTPS 证书。客户端没有跳过证书校验。局域网 NAS 地址通常只在同一局域网 / 可达的 VPN 内可用；公司和外出阅读应使用能访问 NAS 的地址。

## Mac 本地构建

需要 Xcode 16 或以上及已安装的 iOS SDK，不依赖 CocoaPods、第三方 Swift 包或 XcodeGen。

```bash
python3 ios/generate_project.py
open ios/Reader.xcodeproj
# 或在终端构建自签前的 IPA：
bash ios/build-ipa.sh
```

当前 Reader scheme 同时包含单元测试和实际 UI 操作测试。执行 Test 前，先在仓库根目录运行 `python3 tests/fixtures/reader_site.py --mobile-api --port 18998`，再选择 iPhone 或 iPad 模拟器。完整验收范围和独立网页测试命令见 [阅读流程验收说明](../tests/READING_WORKFLOW.md)。新增 Swift 文件后重新运行生成器。

## 真机验收

使用可达的测试服务器和同一测试账号：网页阅读至某章中间并等待保存 → App 打开同一本书接续 → App 阅读后返回书架 → 网页重新打开或切回阅读页验证接续。再断开 App 网络，在已缓存章节中前进，恢复网络验证上传；同时修改两端验证冲突选择。跨账号登录验证缓存相互隔离。

Linux 可以验证 Rust、网页和 HTTP 同步协议；iOS 编译、模拟器测试和真机阅读效果必须分别在 macOS / 真机上验证。不能把静态工程检查描述为 iOS 构建或真机测试通过。
