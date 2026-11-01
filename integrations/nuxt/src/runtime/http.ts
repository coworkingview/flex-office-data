/**
 * Delay before the single retry on 429 or 5xx.
 * `Retry-After` seconds, else `RateLimit-Reset` seconds, else 2s, capped at 10s.
 * Matches the other clients in this repository.
 */
export function retryDelayMs(response: { headers?: { get(name: string): string | null } } | undefined): number {
  const headers = response?.headers
  const retryAfter = headerSeconds(headers, 'retry-after')
  const reset = headerSeconds(headers, 'ratelimit-reset')
  const seconds = retryAfter ?? reset ?? 2
  return Math.min(seconds, 10) * 1000
}

function headerSeconds(
  headers: { get(name: string): string | null } | undefined,
  name: string,
): number | undefined {
  const raw = headers?.get(name)
  if (raw == null || raw.trim() === '') {
    return undefined
  }
  const value = Number(raw)
  if (!Number.isFinite(value) || value < 0) {
    return undefined
  }
  return value
}
