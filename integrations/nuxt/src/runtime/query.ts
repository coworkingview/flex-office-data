import { MAX_PAGE_SIZE } from './constants'
import type { CoworkingPropertiesQuery, CoworkingQueryValue, CoworkingRatesQuery } from './types'

const PROPERTY_KEYS = [
  'locale',
  'city',
  'country',
  'zone',
  'operator',
  'pricingOptionType',
  'minCapacity',
  'minPrice',
  'maxPrice',
  'currency',
  'sortBy',
  'page',
  'pageSize',
  'seed',
] as const satisfies readonly (keyof CoworkingPropertiesQuery)[]

const RATES_KEYS = [
  'locale',
  'city',
  'country',
  'currency',
] as const satisfies readonly (keyof CoworkingRatesQuery)[]

/**
 * Query for `GET /v1/properties`. `locale` falls back to the module default.
 * `pageSize` is clamped to 1..50 because the API rejects a larger page.
 */
export function buildPropertiesQuery(
  locale: string | undefined,
  query: CoworkingPropertiesQuery | undefined,
): Record<string, CoworkingQueryValue> {
  return pickQuery(PROPERTY_KEYS, { locale, ...query })
}

/** Query for `GET /v1/market/rates`. Only the parameters that endpoint accepts. */
export function buildRatesQuery(
  locale: string | undefined,
  query: CoworkingRatesQuery | undefined,
): Record<string, CoworkingQueryValue> {
  return pickQuery(RATES_KEYS, { locale, ...query })
}

function pickQuery(
  keys: readonly string[],
  source: object,
): Record<string, CoworkingQueryValue> {
  const record = source as Record<string, unknown>
  const query: Record<string, CoworkingQueryValue> = {}
  for (const key of keys) {
    const value = record[key]
    if (value === undefined || value === null || value === '') {
      continue
    }
    if (key === 'pageSize') {
      const size = typeof value === 'number' ? value : Number(value)
      if (!Number.isFinite(size)) {
        continue
      }
      query.pageSize = Math.min(MAX_PAGE_SIZE, Math.max(1, Math.trunc(size)))
      continue
    }
    if (typeof value === 'string' || typeof value === 'number') {
      query[key] = value
    }
  }
  return query
}
