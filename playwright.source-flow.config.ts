import { defineConfig } from '@playwright/test'
import base from './playwright.config'

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE

export default defineConfig({
  ...base,
  testMatch: '**/source-reading-flow.spec.ts',
  outputDir: './test-results/source-flow',
  use: { ...base.use, video: 'off' },
  projects: base.projects?.map(project => ({
    ...project,
    use: {
      ...project.use,
      ...(executablePath ? {
        channel: undefined,
        launchOptions: { ...project.use?.launchOptions, executablePath },
      } : {}),
    },
  })),
})
