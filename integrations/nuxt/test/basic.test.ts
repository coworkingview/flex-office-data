import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { $fetch, setup } from '@nuxt/test-utils/e2e'

describe('ssr', async () => {
  await setup({
    rootDir: fileURLToPath(new URL('./fixtures/basic', import.meta.url)),
    server: true,
    browser: false,
  })

  it('renders listings and Price Index attribution from the fixtures', async () => {
    const html = await $fetch<string>('/')
    expect(html).toContain('St. Oberholz Coworking Berlin Mitte')
    expect(html).toContain('CC BY 4.0')
    expect(html).toContain('https://coworkingview.com/en/tools/price-index')
    expect(html).toContain('https://creativecommons.org/licenses/by/4.0/')
    expect(html).toContain('CC-BY-4.0')
    expect(html).toContain('Source: CoworkingView — Coworking spaces in Berlin')
    expect(html).not.toContain('https://example.com/image.webp')
    expect(html).not.toContain('https://example.com/logo.png')
    expect(html).not.toContain('Example description used as a test fixture.')
    expect(html).not.toContain('unexpected query')
    expect(html).not.toContain('unexpected accept')
  })
})
