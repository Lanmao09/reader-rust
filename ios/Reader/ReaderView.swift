import SwiftUI

struct ReaderView: View {
    @StateObject private var session: ReaderSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @AppStorage("reading.fontSize") private var fontSize = 22.0
    @AppStorage("reading.lineSpacing") private var lineSpacing = 12.0
    @AppStorage("reading.serif") private var serif = true
    @AppStorage("reading.theme") private var themeName = ReadingTheme.paper.rawValue
    @AppStorage("reading.keepAwake") private var keepAwake = true
    @State private var controls = true
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var caching = false
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var originalBrightness = UIScreen.main.brightness
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var theme: ReadingTheme { ReadingTheme(rawValue: themeName) ?? .paper }
    init(book: ReaderBook, api: ReaderAPI, library: LocalLibrary) {
        _session = StateObject(wrappedValue: ReaderSession(book: book, api: api, library: library))
    }
    var body: some View {
        VStack(spacing: 0) {
            if controls {
                HStack {
                    Button { Task { await session.close(); dismiss() } } label: { Image(systemName: "chevron.left").padding(10) }.accessibilityLabel("返回书架")
                    Text(session.book.name).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity)
                    Button { showSettings = true } label: { Image(systemName: "textformat.size").padding(10) }.accessibilityLabel("阅读设置")
                }.padding(.horizontal, 10)
            }
            if let conflict = session.conflict {
                VStack(spacing: 10) {
                    Text("另一设备读到了「\(conflict.durChapterTitle ?? "第 \(conflict.chapterIndex + 1) 章")」").font(.footnote)
                    HStack {
                        Button("接着另一设备读") { Task { await session.useCloudProgress() } }.buttonStyle(.borderedProminent)
                        Button("保留本机位置") { Task { await session.keepLocalProgress() } }.buttonStyle(.bordered)
                    }.font(.footnote)
                }.padding(12).frame(maxWidth: .infinity).background(.thinMaterial)
            }
            ZStack {
                ReadingTextView(chapterID: session.chapter?.url ?? "", content: session.content, fraction: session.fraction,
                                fontSize: fontSize, lineSpacing: lineSpacing, theme: theme, useSerif: serif,
                                onProgress: { session.scrolled(to: $0) }, onToggle: { withAnimation(.easeInOut(duration: 0.15)) { controls.toggle() } },
                                onChapterStep: { step in Task { await session.jump(to: session.index + step) } })
                    .opacity(session.loading ? 0.4 : 1)
                if session.loading { ProgressView("正在打开章节…") }
                if let error = session.error {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed").font(.largeTitle)
                        Text(error).font(.callout).multilineTextAlignment(.center)
                        Button("重试") { Task { await session.open() } }.buttonStyle(.bordered)
                    }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).padding(24)
                }
            }
            VStack(spacing: 10) {
                HStack {
                    Text(session.chapter?.title ?? "").lineLimit(1)
                    Spacer()
                    Text("\(session.index + 1)/\(max(1, session.chapters.count)) · \(Int(session.fraction * 100))%")
                        .monospacedDigit()
                }.font(.caption2).foregroundStyle(.secondary)
                if controls {
                    HStack {
                        Button { Task { await session.jump(to: session.index - 1) } } label: { Image(systemName: "chevron.left") }.disabled(session.index == 0 || session.loading).accessibilityLabel("上一章")
                        Spacer()
                        Button { showTOC = true } label: { Label("目录", systemImage: "list.bullet") }
                        Spacer()
                        Button {
                            caching = true
                            Task { await session.cacheMore(); caching = false }
                        } label: { if caching { ProgressView() } else { Image(systemName: "arrow.down.circle") } }.disabled(caching).accessibilityLabel("缓存接下来三十章")
                        Spacer()
                        Button { Task { await session.jump(to: session.index + 1) } } label: { Image(systemName: "chevron.right") }.disabled(session.index >= session.chapters.count - 1 || session.loading).accessibilityLabel("下一章")
                    }.padding(.vertical, 5)
                    Text(session.syncStatus).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("reader.syncStatus")
                }
            }.padding(.horizontal, 24).padding(.vertical, 10)
        }
        .background(Color(theme.background)).foregroundStyle(Color(theme.foreground))
        .statusBarHidden(!controls)
        .preferredColorScheme(theme == .night ? .dark : .light)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showTOC) { chapterList }
        .sheet(isPresented: $showSettings) { settings }
        .task { await session.open() }
        .onAppear { originalBrightness = UIScreen.main.brightness; UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear { UIScreen.main.brightness = originalBrightness; UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: keepAwake) { UIApplication.shared.isIdleTimerDisabled = $0 }
        .onChange(of: phase) { phase in
            if phase == .active {
                UIScreen.main.brightness = CGFloat(brightness)
                UIApplication.shared.isIdleTimerDisabled = keepAwake
                Task { await session.reconcile() }
            } else {
                UIScreen.main.brightness = originalBrightness
                UIApplication.shared.isIdleTimerDisabled = false
                saveBeforeSuspending()
            }
        }
    }
    private func saveBeforeSuspending() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save reading position") {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
        }
        Task {
            await session.flush()
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
        }
    }
    private var chapterList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(Array(session.chapters.enumerated()), id: \.element.url) { offset, chapter in
                    Button {
                        showTOC = false
                        Task { await session.jump(to: offset) }
                    } label: {
                        HStack { Text(chapter.title); Spacer(); if offset == session.index { Image(systemName: "bookmark.fill") } }
                    }.id(offset)
                }.onAppear { proxy.scrollTo(session.index, anchor: .center) }
            }.navigationTitle("目录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showTOC = false } } }
        }
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("纸张") {
                    Picker("主题", selection: $themeName) { ForEach(ReadingTheme.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
                }
                Section("排版") {
                    Text("字号 \(Int(fontSize))")
                    Slider(value: $fontSize, in: 16...36, step: 1).accessibilityIdentifier("reading.fontSize")
                    Text("行间距 \(Int(lineSpacing))")
                    Slider(value: $lineSpacing, in: 4...24, step: 1)
                    Toggle("宋体阅读", isOn: $serif)
                }
                Section("屏幕") {
                    Slider(value: $brightness, in: 0.05...1) { Text("亮度") }
                        .onChange(of: brightness) { UIScreen.main.brightness = CGFloat($0) }
                    Toggle("阅读时保持屏幕常亮", isOn: $keepAwake)
                }
                Section { Text("上下滑动阅读；轻点左右边缘翻一屏，中间区域显示或隐藏工具栏。横屏和 iPad 会自动限制正文宽度。").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("阅读设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showSettings = false } } }
        }.presentationDetents([.medium, .large])
    }
}
