import SwiftUI

@MainActor
final class ReaderSession: ObservableObject {
    @Published var book: ReaderBook
    @Published var chapters: [ReaderChapter] = []
    @Published var index = 0
    @Published var fraction = 0.0
    @Published var content = ""
    @Published var loading = true
    @Published var error: String?
    @Published var syncStatus = "正在读取进度"
    @Published var conflict: ReaderBook?
    private let api: ReaderAPI
    private let library: LocalLibrary
    private var revision: Int64
    private var dirty = false
    private var saving = false
    private var generation = 0
    private var autosave: Task<Void, Never>?
    private var prefetch: Task<Void, Never>?
    var chapter: ReaderChapter? { chapters.indices.contains(index) ? chapters[index] : nil }

    init(book: ReaderBook, api: ReaderAPI, library: LocalLibrary) {
        self.book = book; self.api = api; self.library = library
        revision = book.revision; index = book.chapterIndex; fraction = book.fraction
    }
    func open() async {
        do {
            let latest = try await api.book(book.bookUrl)
            book = latest; revision = latest.revision; index = latest.chapterIndex; fraction = latest.fraction
            syncStatus = "已读取云端进度"
        } catch { syncStatus = "离线阅读 · 联网后同步" }
        if let pending = await library.pending()[book.bookUrl] {
            index = pending.index; fraction = ProgressPosition.decode(pending.position)
            dirty = true
            if pending.expectedUpdatedAt != revision { conflict = book }
            revision = pending.expectedUpdatedAt
        }
        do {
            chapters = try await api.chapters(book)
            try await library.write(chapters, for: "toc:" + book.bookUrl)
        } catch {
            chapters = await library.read("toc:" + book.bookUrl, as: [ReaderChapter].self) ?? []
            if chapters.isEmpty { self.error = "尚无离线目录，请联网打开一次这本书。" }
        }
        // A paginated TOC can still be filling on the server. Never move a saved
        // position backwards just because the current response is incomplete.
        guard chapters.indices.contains(index) else {
            loading = false
            error = "当前目录尚未包含已保存的章节。请稍后联网重试，原阅读位置已保留。"
            return
        }
        await loadContent()
        if dirty && conflict == nil { await flush() }
    }
    func loadContent() async {
        loading = true
        error = nil
        defer { loading = false }
        guard let chapter else { error = "没有可用章节，请联网刷新目录。"; return }
        let targetURL = chapter.url
        let key = "chapter:" + book.bookUrl + ":" + targetURL
        if let cached = await library.read(key, as: String.self) {
            content = cached
        } else {
            do {
                let text = try await api.content(chapter, book: book)
                guard self.chapter?.url == targetURL else { return }
                content = text
                try await library.write(text, for: key)
            } catch { self.error = "该章节未缓存。\(error.localizedDescription)"; content = "" }
        }
        prefetch?.cancel()
        let following = Array(chapters.dropFirst(index + 1).prefix(3))
        let api = self.api, library = self.library, book = self.book
        prefetch = Task {
            for chapter in following {
                guard !Task.isCancelled else { return }
                let key = "chapter:" + book.bookUrl + ":" + chapter.url
                if await library.read(key, as: String.self) != nil { continue }
                if let text = try? await api.content(chapter, book: book) { try? await library.write(text, for: key) }
            }
        }
    }
    func jump(to next: Int) async {
        guard chapters.indices.contains(next), !loading else { return }
        index = next; fraction = 0
        await recordChange()
        await loadContent()
        await flush()
    }
    func scrolled(to progress: Double) {
        guard !loading, abs(progress - fraction) > 0.00005 else { return }
        fraction = min(1, max(0, progress))
        Task { await recordChange() }
    }
    private func recordChange() async {
        dirty = true; generation += 1
        syncStatus = conflict == nil ? "进度已保存在本机" : "设备进度不同，等待选择"
        do { try await library.enqueue(payload()) }
        catch { self.error = "本机进度保存失败：\(error.localizedDescription)" }
        autosave?.cancel()
        autosave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            await self?.flush()
        }
    }
    private func payload() -> ProgressWrite {
        ProgressWrite(bookUrl: book.bookUrl, index: chapter?.index ?? index,
                      position: ProgressPosition.encode(fraction), expectedUpdatedAt: revision)
    }
    func flush() async {
        guard dirty, !saving, conflict == nil, !chapters.isEmpty else { return }
        saving = true
        defer { saving = false }
        let sent = payload(), sentGeneration = generation
        do {
            try await library.enqueue(sent)
            let result = try await api.save(sent)
            if !result.accepted {
                conflict = result.book; syncStatus = "另一设备已更新进度"; return
            }
            revision = result.book.revision; book = result.book
            if generation == sentGeneration {
                dirty = false
                try await library.acknowledge(sent)
                syncStatus = "已同步到网页"
            } else {
                try await library.enqueue(payload())
                syncStatus = "正在同步新的位置"
            }
        } catch { syncStatus = "离线进度已保留 · 联网后重试" }
    }
    func reconcile() async {
        guard !loading, !saving, conflict == nil else { return }
        do {
            let latest = try await api.book(book.bookUrl)
            if latest.revision != revision {
                if dirty { conflict = latest; syncStatus = "另一设备已更新进度" }
                else { await adopt(latest) }
            } else { await flush() }
        } catch { syncStatus = "离线阅读 · 联网后重试" }
    }
    func useCloudProgress() async {
        guard let latest = conflict else { return }
        autosave?.cancel()
        do { try await library.discardPending(bookURL: book.bookUrl) }
        catch { self.error = error.localizedDescription; return }
        conflict = nil; dirty = false
        await adopt(latest)
    }
    func keepLocalProgress() async {
        guard let latest = conflict else { return }
        revision = latest.revision; conflict = nil
        await recordChange()
        await flush()
    }
    private func adopt(_ latest: ReaderBook) async {
        let previous = index
        book = latest; revision = latest.revision
        index = latest.chapterIndex; fraction = latest.fraction
        if previous != index { await loadContent() }
        syncStatus = "已接续另一设备的进度"
    }
    func cacheMore() async {
        let following = Array(chapters.dropFirst(index).prefix(30))
        do {
            for (offset, chapter) in following.enumerated() {
                try Task.checkCancellation()
                let key = "chapter:" + book.bookUrl + ":" + chapter.url
                if await library.read(key, as: String.self) == nil {
                    let text = try await api.content(chapter, book: book)
                    try await library.write(text, for: key)
                }
                syncStatus = "缓存章节 \(offset + 1)/\(following.count)"
            }
            syncStatus = "已缓存接下来的 \(following.count) 章"
        } catch { self.error = "缓存未完成，已下载的章节仍可阅读。\(error.localizedDescription)" }
    }
    func close() async { autosave?.cancel(); prefetch?.cancel(); await flush() }
}
