import { COWORKINGVIEW_API_URL } from './constants'

/**
 * Absolute origin for `$fetch`. A relative module `baseURL` (tests use `/`)
 * is resolved against the current request origin so the call stays on that server.
 */
export function resolveBaseURL(configured: string | undefined, origin: string): string {
  const value = configured && configured.length > 0 ? configured : COWORKINGVIEW_API_URL
  if (/^https?:\/\//i.test(value)) {
    return value.replace(/\/+$/, '')
  }
  const url = new URL(value, origin.endsWith('/') ? origin : `${origin}/`)
  return url.toString().replace(/\/+$/, '')
}
