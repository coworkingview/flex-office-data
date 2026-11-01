import type { CoworkingPropertiesResponse, CoworkingProperty, CoworkingRatesResponse } from './types'

const DROPPED_PROPERTY_KEYS = new Set(['images', 'excerpt', 'description'])

/**
 * Drops photos, logos and description text from a `GET /v1/properties` body.
 * Every other field is kept, including `meta.citation` and `meta.catalogueNotice`.
 */
export function sanitizePropertiesResponse(body: unknown): CoworkingPropertiesResponse {
  const record = asRecord(body)
  const rows = Array.isArray(record?.data) ? record.data.map(sanitizeProperty) : []
  const meta = asRecord(record?.meta) ?? {}
  return {
    data: rows,
    meta,
  }
}

/** Price Index payloads are returned whole, attribution included. */
export function sanitizeRatesResponse(body: unknown): CoworkingRatesResponse {
  const record = asRecord(body)
  const data = asRecord(record?.data) ?? {}
  const meta = asRecord(record?.meta)
  return meta ? { data, meta } : { data }
}

function sanitizeProperty(value: unknown): CoworkingProperty {
  const source = asRecord(value) ?? {}
  const property: Record<string, unknown> = {}
  for (const [key, item] of Object.entries(source)) {
    if (DROPPED_PROPERTY_KEYS.has(key)) {
      continue
    }
    if (key === 'operator') {
      const operator = asRecord(item)
      if (!operator) {
        continue
      }
      const { logo: _logo, ...rest } = operator
      property.operator = rest
      continue
    }
    property[key] = item
  }
  return property as unknown as CoworkingProperty
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>
  }
  return null
}
