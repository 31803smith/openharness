// Pictures of a viewer, as the person watching the pane would see it: headless Chromium from the
// Builder's own pinned playwright-core, never the machine's browser.
import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const TOOLCHAIN = dirname(dirname(fileURLToPath(import.meta.url)))
export const BROWSERS = join(TOOLCHAIN, '.playwright')

async function loadChromium() {
  process.env.PLAYWRIGHT_BROWSERS_PATH ??= BROWSERS
  let mod
  try {
    mod = await import(join(TOOLCHAIN, 'node_modules', 'playwright-core', 'index.mjs'))
  } catch {
    throw new Error('playwright-core is not installed in the Builder toolchain: run its setup')
  }
  return mod.chromium ?? mod.default.chromium
}

/** One browser for a burst of pictures (a proof's frames); close it when done. */
export async function openBrowser() {
  const chromium = await loadChromium()
  // Metal-backed ANGLE on macOS: WebGL viewers (3D, maps) render at full speed rather than through
  // SwiftShader at a few frames a second, which is what made a game's first frames black.
  const args = process.platform === 'darwin' ? ['--use-angle=metal', '--enable-gpu'] : ['--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  return chromium.launch({ args })
}

/**
 * Snapshot `url` into `out` (.png or .jpg by extension). `settleMs` lets a viewer finish its first
 * render after load: a viewer holds a server-sent-events stream open, so "network idle" never comes.
 */
export async function snapshot(url, out, { browser, width = 1600, height = 1000, theme = 'dark', settleMs = 2500, quality = 85 } = {}) {
  const own = !browser
  browser ??= await openBrowser()
  try {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, colorScheme: theme })
    const page = await context.newPage()
    const messages = []
    page.on('console', (msg) => { if (msg.type() === 'error') messages.push(msg.text().slice(0, 300)) })
    page.on('pageerror', (error) => messages.push(String(error.message ?? error).slice(0, 300)))
    await page.goto(url, { waitUntil: 'load', timeout: 45_000 })
    await page.waitForTimeout(settleMs)
    const jpeg = /\.jpe?g$/i.test(out)
    await page.screenshot({ path: out, type: jpeg ? 'jpeg' : 'png', ...(jpeg ? { quality } : {}) })
    const title = await page.title().catch(() => '')
    await context.close()
    return { out, title, consoleErrors: messages }
  } finally {
    if (own) await browser.close()
  }
}

export function browsersInstalled() {
  return existsSync(BROWSERS)
}
