import { test, expect } from '@playwright/test'
import { spawn, type ChildProcess } from 'node:child_process'
import { createInterface } from 'node:readline'
import { randomBytes } from 'node:crypto'
import { openSettings } from './support/app'

let fixture: ChildProcess
let site = ''

test.describe('Source import to reading against the real Rust server', () => {
  test.skip(process.env.READER_TEST_SERVER !== '1', 'Requires an explicitly designated disposable local test server.')
  test.beforeAll(async () => {
    fixture = spawn('python3', ['tests/fixtures/reader_site.py'], { stdio: ['ignore', 'pipe', 'inherit'] })
    site = await new Promise<string>((resolve, reject) => {
      const lines = createInterface({ input: fixture.stdout! })
      const timer = setTimeout(() => reject(new Error('Fixture site did not start')), 10_000)
      lines.once('line', (line) => { clearTimeout(timer); resolve(JSON.parse(line).url) })
      fixture.once('error', reject)
    })
  })
  test.afterAll(() => fixture?.kill())

  test('imports a source file, searches, shelves, reads, changes chapter and resumes on another client', async ({ page, request, browser, baseURL }, testInfo) => {
    test.setTimeout(90_000)
    expect(['127.0.0.1', 'localhost']).toContain(new URL(baseURL!).hostname)
    const username = 'flow' + randomBytes(6).toString('hex')
    const password = randomBytes(16).toString('hex')
    const created = await request.post('/reader3/login', { data: { username, password, isLogin: false } })
    expect(created.ok()).toBeTruthy()
    const createdData = await created.json()
    expect(createdData.isSuccess).toBe(true)
    expect((await (await request.get('/reader3/getUserInfo')).json()).data.secure).toBe(true)

    await page.goto('/#/')
    await expect(page.locator('#username')).toBeVisible()
    await page.locator('#username').fill(username)
    await page.locator('#password').fill(password)
    await page.getByRole('button', { name: '登 录' }).click()
    await expect(page.locator('.login-modal')).toHaveCount(0)
    await expect(page.locator('.settings-drawer')).toHaveCount(0)

    await openSettings(page)
    await page.getByRole('button', { name: '书源管理', exact: true }).click()
    const sourceResponse = await request.get(site + '/source.json')
    await page.locator('.source-modal input[type=file]').setInputFiles({ name: 'fixture-source.json', mimeType: 'application/json', buffer: await sourceResponse.body() })
    await expect(page.locator('.source-list-slot')).toContainText('受控测试书源')
    await page.locator('.source-manager-header').getByTitle('关闭', { exact: true }).click()
    await expect(page.locator('.settings-drawer')).toHaveCount(0)

    await page.getByPlaceholder('搜索书籍...').fill('测试小说')
    await page.getByPlaceholder('搜索书籍...').press('Enter')
    const result = page.locator('.search-results .book-card').filter({ hasText: '书源全流程测试小说' })
    await expect(result).toHaveCount(1)
    const save = page.waitForResponse(r => r.url().endsWith('/saveBook') && r.request().method() === 'POST')
    await result.getByRole('button', { name: '加入书架' }).click()
    expect((await (await save).json()).isSuccess).toBe(true)
    await page.getByRole('button', { name: '返回书架', exact: true }).click()
    await page.locator('.book-card').filter({ hasText: '书源全流程测试小说' }).locator('.book-name').click()
    await expect(page.locator('.chapter-content .chapter-title')).toContainText('第1章')
    await expect(page.locator('.chapter-text')).toContainText('第1章正文')
    await page.getByTitle('下一章', { exact: true }).click()
    await expect(page.locator('.chapter-content .chapter-title')).toContainText('第2章')
    await expect(page.locator('.chapter-text')).toContainText('第2章正文')

    const scroll = page.locator('.reader-scroll-container')
    const distance = await scroll.evaluate(el => (el.scrollHeight - el.clientHeight) * 0.4)
    await scroll.hover()
    await page.mouse.wheel(0, distance)
    await expect.poll(async () => scroll.evaluate(el => el.scrollTop / Math.max(1, el.scrollHeight - el.clientHeight))).toBeCloseTo(0.4, 1)
    const uploaded = page.waitForResponse(r => r.url().endsWith('/syncBookProgress') && r.request().method() === 'POST' && r.request().postDataJSON().position > 3000)
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange')) })
    const progress = (await (await uploaded).json()).data
    expect(progress.accepted).toBe(true)
    expect(progress.book.durChapterPos).toBeGreaterThan(3000)
    expect(progress.book.durChapterPos).toBeLessThan(5000)
    await testInfo.attach('desktop-reading', { body: await page.screenshot(), contentType: 'image/png' })

    const mobileLogin = await request.post('/reader3/login', { data: { username, password, isLogin: true } })
    const mobileToken = (await mobileLogin.json()).data.accessToken
    const mobile = await browser.newContext({ viewport: { width: 390, height: 844 } })
    await mobile.addInitScript(token => localStorage.setItem('accessToken', token), mobileToken)
    const mobilePage = await mobile.newPage()
    await mobilePage.goto(baseURL! + '/#/')
    await mobilePage.locator('.book-card').filter({ hasText: '书源全流程测试小说' }).locator('.book-name').click()
    await expect(mobilePage.locator('.chapter-content .chapter-title')).toContainText('第2章')
    await expect(mobilePage.locator('.chapter-text')).toContainText('第2章正文')
    await expect.poll(async () => mobilePage.locator('.reader-scroll-container').evaluate(el => el.scrollTop / Math.max(1, el.scrollHeight - el.clientHeight))).toBeCloseTo(progress.book.durChapterPos / 10000, 1)
    await testInfo.attach('mobile-browser-reading', { body: await mobilePage.screenshot(), contentType: 'image/png' })
    await mobile.close()
    const stats = await (await request.get(site + '/__state')).json()
    expect(stats.requests['/search']).toBeGreaterThan(0)
    expect(stats.requests['/toc/1']).toBeGreaterThan(0)
    expect(stats.requests['/chapter/1']).toBeGreaterThan(0)
    expect(stats.requests['/chapter/2']).toBeGreaterThan(0)
  })
})
