/** Public CoworkingView API. No key. */
export const COWORKINGVIEW_API_URL = 'https://api.coworkingview.com'

/** Same shape as the other clients in this repository. */
export const USER_AGENT = 'coworkingview-nuxt/0.1.0 (+https://github.com/coworkingview/flex-office-data)'

/** `pageSize` above 50 is rejected by the API (`400`, expected number <= 50). */
export const MAX_PAGE_SIZE = 50

export const REQUEST_TIMEOUT_MS = 20_000

/** One retry, and only for the statuses the shared spec retries. */
export const RETRY_STATUS_CODES = [429, 500, 502, 503, 504] as const
