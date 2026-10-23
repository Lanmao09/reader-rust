import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useAppStore } from './app'
import { useReaderStore } from './reader'
import { getBookContent, getChapterList, getShelfBook, syncBookProgress } from '../api/bookshelf'
import { getBrowserCachedChapter } from '../utils/browserCache'

vi.mock('../api/bookshelf', () => ({
  getChapterList: vi.fn(),
  getBookContent: vi.fn(),
  saveBookProgress: vi.fn(),
  getShelfBook: vi.fn(),
  syncBookProgress: vi.fn(),
  setBookSource: vi.fn(),
}))

vi.mock('../api/bookmark', () => ({
  getBookmarks: vi.fn(),
  saveBookmark: vi.fn(),
  deleteBookmark: vi.fn(),
  deleteBookmarks: vi.fn(),
}))

vi.mock('../api/replaceRule', () => ({
  getReplaceRules: vi.fn(),
}))

vi.mock('../utils/browserCache', () => ({
  getBrowserCachedChapter: vi.fn(),
  setBrowserCachedChapter: vi.fn(),
}))

vi.mock('../utils/recentBooks', () => ({
  saveRecentReadBook: vi.fn(),
}))

vi.mock('../utils/openaiSpeech', () => ({
  DEFAULT_OPENAI_BASE_URL: 'https://api.openai.com/v1',
  requestOpenAISpeechAudio: vi.fn(),
}))

describe('reader local txt chapters', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    const storage = new Map<string, string>()
    vi.stubGlobal('localStorage', {
      getItem: vi.fn((key: string) => storage.get(key) ?? null),
      setItem: vi.fn((key: string, value: string) => storage.set(key, value)),
      removeItem: vi.fn((key: string) => storage.delete(key)),
      clear: vi.fn(() => storage.clear()),
    })
    vi.mocked(getBookContent).mockReset()
    vi.mocked(getBrowserCachedChapter).mockReset()
    vi.mocked(syncBookProgress).mockReset()
  })

  it('keeps edits made while an earlier progress save is in flight', async () => {
    const store = useReaderStore()
    store.book = { name: '测试书', author: '作者', bookUrl: 'book1', origin: 'source' }
    store.setChapterScrollProgress(0.2)
    let finish!: (value: { accepted: boolean; book: typeof store.book }) => void
    vi.mocked(syncBookProgress).mockReturnValue(new Promise((resolve) => { finish = resolve }) as never)
    const saving = store.flushProgressToServer()
    store.setChapterScrollProgress(0.5)
    finish({ accepted: true, book: { ...store.book, durChapterTime: 123 } })
    await saving
    vi.mocked(syncBookProgress).mockResolvedValue({ accepted: true, book: { ...store.book, durChapterTime: 124 } })
    await store.flushProgressToServer()
    expect(syncBookProgress).toHaveBeenLastCalledWith(expect.objectContaining({ position: 5000, expectedUpdatedAt: 123 }))
  })

  it('opens the latest cloud chapter even when the bookshelf entry is stale', async () => {
    const store = useReaderStore()
    const stale = { name: '测试书', author: '作者', bookUrl: 'book1', origin: 'source', durChapterIndex: 1 }
    vi.mocked(getShelfBook).mockResolvedValue({ ...stale, durChapterIndex: 9, durChapterTime: 200 })
    vi.mocked(getChapterList).mockResolvedValue([{ index: 9, url: 'chapter9', title: '第十章' }])
    await store.loadBook(stale)
    expect(store.currentIndex).toBe(9)
    expect(store.book?.durChapterTime).toBe(200)
  })

  it('restores the first scaled position near the start instead of jumping to the chapter end', async () => {
    const store = useReaderStore()
    store.book = { name: '测试书', author: '作者', bookUrl: 'book1', origin: 'local-txt', durChapterIndex: 0, durChapterPos: 1 }
    store.chapters = [{ index: 0, url: 'chapter0', title: '第一章' }]
    vi.mocked(getBookContent).mockResolvedValue('测试正文')
    await store.loadChapter(0)
    expect(store.chapterScrollProgress).toBe(0.0001)
  })

  it('retains both positions on a conflict and waits for an explicit decision', async () => {
    const store = useReaderStore()
    store.book = { name: '测试书', author: '作者', bookUrl: 'book1', origin: 'source' }
    store.setChapterScrollProgress(0.4)
    const remote = { ...store.book, durChapterIndex: 8, durChapterTime: 200 }
    vi.mocked(syncBookProgress).mockResolvedValue({ accepted: false, book: remote })
    await store.flushProgressToServer()
    expect(store.pendingRemoteProgress).toEqual(remote)
    expect(store.chapterScrollProgress).toBe(0.4)
    await store.flushProgressToServer(true)
    expect(syncBookProgress).toHaveBeenCalledTimes(1)
    vi.mocked(syncBookProgress).mockResolvedValue({ accepted: true, book: { ...remote, durChapterTime: 201 } })
    await store.resolveRemoteProgress(true)
    expect(syncBookProgress).toHaveBeenLastCalledWith(expect.objectContaining({ expectedUpdatedAt: 200, position: 4000 }))
    expect(store.pendingRemoteProgress).toBeNull()
  })

  it('keeps unsent progress after a failed network save', async () => {
    const store = useReaderStore()
    store.book = { name: '测试书', author: '作者', bookUrl: 'book1', origin: 'source' }
    store.setChapterScrollProgress(0.7)
    vi.mocked(syncBookProgress).mockRejectedValue(new Error('offline'))
    await store.flushProgressToServer()
    vi.mocked(syncBookProgress).mockResolvedValue({ accepted: true, book: { ...store.book, durChapterTime: 101 } })
    await store.flushProgressToServer()
    expect(syncBookProgress).toHaveBeenCalledTimes(2)
  })

  it('fetches uploaded local txt content from backend even when browser reports offline', async () => {
    vi.mocked(getBookContent).mockResolvedValue('本地正文')
    vi.mocked(getBrowserCachedChapter).mockResolvedValue(null)
    const appStore = useAppStore()
    const readerStore = useReaderStore()
    appStore.setOnlineStatus(false)
    readerStore.book = {
      name: '本地书',
      author: '本地导入',
      origin: 'local-txt',
      bookUrl: 'local-txt:abc123',
    }
    readerStore.chapters = [
      { title: '第一章', url: 'local-txt:abc123#0', index: 0 },
    ]

    await expect(readerStore.fetchChapterContent(0)).resolves.toBe('本地正文')

    expect(getBrowserCachedChapter).not.toHaveBeenCalled()
    expect(getBookContent).toHaveBeenCalledWith({
      chapterUrl: 'local-txt:abc123#0',
      bookSourceUrl: 'local-txt',
      refresh: 0,
    })
  })
})
