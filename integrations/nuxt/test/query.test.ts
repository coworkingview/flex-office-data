import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { COWORKINGVIEW_API_URL, USER_AGENT } from '../src/runtime/constants'
import { retryDelayMs } from '../src/runtime/http'
import { buildPropertiesQuery, buildRatesQuery } from '../src/runtime/query'
import { sanitizePropertiesResponse, sanitizeRatesResponse } from '../src/runtime/sanitize'
import { resolveBaseURL } from '../src/runtime/base-url'

function readJson(relativePath: string) {
  return JSON.parse(readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8'))
}

describe('queries', () => {
  it('sends the properties parameters the API documents', () => {
    expect(buildPropertiesQuery('en', { city: 'berlin' })).toEqual({
      locale: 'en',
      city: 'berlin',
    })
    expect(buildPropertiesQuery('en', {
      locale: 'de',
      city: 'madrid',
      country: 'spain',
      zone: 'centro',
      operator: 'regus',
      pricingOptionType: 'meeting_room',
      minCapacity: 4,
      minPrice: 10,
      maxPrice: 40,
      currency: 'EUR',
      sortBy: 'price-asc',
      page: 2,
      pageSize: 3,
      seed: 7,
    })).toEqual({
      locale: 'de',
      city: 'madrid',
      country: 'spain',
      zone: 'centro',
      operator: 'regus',
      pricingOptionType: 'meeting_room',
      minCapacity: 4,
      minPrice: 10,
      maxPrice: 40,
      currency: 'EUR',
      sortBy: 'price-asc',
      page: 2,
      pageSize: 3,
      seed: 7,
    })
  })

  it('caps pageSize at 50 and drops values the endpoint does not take', () => {
    expect(buildPropertiesQuery('en', { city: 'berlin', pageSize: 51 }).pageSize).toBe(50)
    expect(buildPropertiesQuery('en', { city: '', pageSize: 0 })).toEqual({
      locale: 'en',
      pageSize: 1,
    })
    const rates = buildRatesQuery('en', { city: 'berlin', currency: 'USD' })
    expect(rates).toEqual({ locale: 'en', city: 'berlin', currency: 'USD' })
    expect(rates).not.toHaveProperty('pageSize')
    expect(rates).not.toHaveProperty('pricingOptionType')
  })
})

describe('fixtures', () => {
  const properties = readJson('./fixtures/basic/server/fixtures/properties_berlin.json')
  const rates = readJson('./fixtures/basic/server/fixtures/market_rates_berlin_usd.json')

  it('uses the shared spec fixtures', () => {
    expect(properties).toEqual(readJson('../../../spec/fixtures/properties_berlin.json'))
    expect(rates).toEqual(readJson('../../../spec/fixtures/market_rates_berlin_usd.json'))
  })

  it('removes photos, logos and description text and keeps the citation', () => {
    const sanitized = sanitizePropertiesResponse(properties)
    const encoded = JSON.stringify(sanitized)
    expect(sanitized.data[0]?.slug).toBe('sankt-oberholz-rosenthaler-berlin')
    expect(sanitized.data[0]?.operator).toEqual({ slug: 'sankt-oberholz', name: 'St. Oberholz' })
    expect(sanitized.data[0]?.city).toEqual({ slug: 'berlin', name: 'Berlin' })
    expect(sanitized.meta.citation?.text).toContain('https://coworkingview.com/en/coworking/berlin')
    expect(sanitized.meta.catalogueNotice).toContain('No licence')
    expect(encoded).not.toContain('example.com/image.webp')
    expect(encoded).not.toContain('example.com/logo.png')
    expect(encoded).not.toContain('Example description used as a test fixture.')
  })

  it('keeps the Price Index attribution the API returns', () => {
    const sanitized = sanitizeRatesResponse(rates)
    expect(sanitized.data.license).toBe('CC-BY-4.0')
    expect(sanitized.data.licenseUrl).toBe('https://creativecommons.org/licenses/by/4.0/')
    expect(sanitized.data.attribution).toContain('CoworkingView Price Index')
    expect(sanitized.data.attribution).toContain('CC BY 4.0')
    expect(sanitized.data.cities?.[0]?.city?.slug).toBe('berlin')
    expect(sanitized.data.cities?.[0]?.figures?.[0]?.median?.amount).toBe(337)
    expect(sanitized.meta?.contractVersion).toBe('1.0.0')
  })
})

describe('http', () => {
  it('uses the public API and the shared User-Agent', () => {
    expect(COWORKINGVIEW_API_URL).toBe('https://api.coworkingview.com')
    expect(USER_AGENT).toBe('coworkingview-nuxt/0.1.0 (+https://github.com/coworkingview/flex-office-data)')
    expect(resolveBaseURL(undefined, 'http://127.0.0.1:3000')).toBe('https://api.coworkingview.com')
    expect(resolveBaseURL('/', 'http://127.0.0.1:3000')).toBe('http://127.0.0.1:3000')
    expect(resolveBaseURL('https://api.coworkingview.com/', 'http://127.0.0.1:3000')).toBe('https://api.coworkingview.com')
  })

  it('waits Retry-After, else RateLimit-Reset, else 2s, and caps at 10s', () => {
    expect(retryDelayMs(undefined)).toBe(2000)
    expect(retryDelayMs({ headers: { get: name => (name === 'retry-after' ? '3' : null) } })).toBe(3000)
    expect(retryDelayMs({ headers: { get: name => (name === 'ratelimit-reset' ? '4' : null) } })).toBe(4000)
    expect(retryDelayMs({ headers: { get: () => '30' } })).toBe(10_000)
  })
})
