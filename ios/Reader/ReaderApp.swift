import SwiftUI
import UIKit

@main
struct ReaderApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            BookshelfView().environmentObject(model).tint(Color(red: 0.55, green: 0.31, blue: 0.16))
        }
    }
}

struct BookshelfView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @State private var showConnection = false
    @State private var selectedBook: ReaderBook?
    @State private var search = ""
    private var books: [ReaderBook] {
        model.books.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("把故事，接着读。")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                        Text(model.status).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                    if let error = model.error {
                        Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.connection == nil {
                        VStack(alignment: .leading, spacing: 18) {
                            Image(systemName: "books.vertical").font(.system(size: 42)).foregroundStyle(.brown)
                            Text("一份书架，在每台设备上继续。").font(.title3.bold())
                            Text("连接你自己的 reader-rust 服务，使用和电脑网页相同的账号。").foregroundStyle(.secondary)
                            Button("连接阅读服务器") { showConnection = true }.buttonStyle(.borderedProminent)
                        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22))
                    } else if books.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "books.vertical").font(.largeTitle)
                            Text(search.isEmpty ? "书架还空着" : "没有找到这本书").font(.headline)
                            Text("在电脑网页添加书籍或导入 TXT / EPUB，然后下拉刷新。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if let url = model.connection?.baseURL { Link("打开网页管理书籍与书源", destination: url) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 20)], alignment: .leading, spacing: 28) {
                            ForEach(books) { book in
                                Button { selectedBook = book } label: { BookTile(book: book) }.buttonStyle(.plain)
                                    .accessibilityIdentifier("book:" + book.bookUrl)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .background(colorScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Color(red: 0.97, green: 0.96, blue: 0.93))
            .navigationTitle("阅间")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showConnection = true } label: { Image(systemName: "network") }.accessibilityLabel("服务器与账号")
                }
            }
            .searchable(text: $search, prompt: "搜索书架中的书名或作者")
            .refreshable { await model.refresh() }
            .overlay { if model.loading && model.books.isEmpty { ProgressView() } }
            .sheet(isPresented: $showConnection) { ConnectionView() }
            .fullScreenCover(item: $selectedBook, onDismiss: { Task { await model.refresh() } }) { book in
                if let api = model.api, let library = model.library { ReaderView(book: book, api: api, library: library) }
            }
            .task { await model.refresh() }
            .onChange(of: phase) { phase in
                if phase == .active && selectedBook == nil { Task { await model.refresh() } }
            }
        }
    }
}

private struct BookTile: View {
    let book: ReaderBook
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [.brown.opacity(0.75), Color(red: 0.32, green: 0.24, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "book.closed").font(.title2).opacity(0.6)
                    Text(book.name).font(.system(size: 23, weight: .medium, design: .serif)).lineLimit(4)
                    Spacer()
                    Text(book.author).font(.caption).lineLimit(1).opacity(0.75)
                }.foregroundStyle(.white).padding(20)
            }.aspectRatio(0.72, contentMode: .fit).shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 4)
            Text(book.name).font(.headline).lineLimit(1)
            Text(book.durChapterTitle ?? "从第一章开始").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let total = book.totalChapterNum, total > 0 {
                ProgressView(value: min(1, (Double(book.chapterIndex) + book.fraction) / Double(total))).tint(.brown)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var secureKey = ""
    @State private var connecting = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://你的阅读服务器", text: $server)
                        .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connection.server")
                } header: { Text("服务器地址") } footer: {
                    Text("可填写 NAS 的局域网地址或反代地址，也支持端口和子路径。离家后需要能访问该地址；公网连接建议使用 HTTPS。")
                }
                Section {
                    TextField("与网页相同的账号", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connection.username")
                    SecureEntry(placeholder: "密码", text: $password, contentType: .password, identifier: "connection.password")
                        .frame(maxWidth: .infinity, minHeight: 24)
                } header: { Text("登录") } footer: { Text("密码仅用于本次登录。登录凭证保存在本机钥匙串；不同服务器和账号的离线缓存相互隔离。") }
                Section {
                    SecureEntry(placeholder: "服务器安全密钥（如有）", text: $secureKey, contentType: nil, identifier: "connection.secureKey")
                        .frame(maxWidth: .infinity, minHeight: 24)
                } header: { Text("高级选项") } footer: { Text("仅当网页也要求安全密钥时填写。未开启账号模式的服务器可留空账号和密码。") }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connection.error") } }
                Section {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        connecting = true; error = nil
                        Task {
                            do {
                                try await model.connect(server: server, username: username, password: password, secureKey: secureKey)
                                password = ""; dismiss()
                            } catch { self.error = error.localizedDescription }
                            connecting = false
                        }
                    } label: {
                        HStack { Spacer(); if connecting { ProgressView() }; Text(connecting ? "正在连接…" : "连接并同步书架"); Spacer() }
                    }.disabled(connecting || server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("服务器与账号").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(connecting) } }
            .onAppear {
                server = model.connection?.baseURL.absoluteString ?? ""
                username = model.connection?.username ?? ""
                secureKey = model.connection?.secureKey ?? ""
            }
        }
    }
}
