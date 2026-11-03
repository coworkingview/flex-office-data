export const VERSION = '0.1.0';

export const DEFAULT_URL = 'https://api.coworkingview.com/v1/market/rates';

export const USER_AGENT =
  `leaflet-coworkingview/${VERSION} (+https://github.com/coworkingview/flex-office-data)`;

const FALLBACK_WAIT_MS = 2000;
const MAX_WAIT_MS = 10000;
const TIMEOUT_MS = 20000;

export class CoworkingViewError extends Error {
  constructor(message, fields = {}) {
    super(message);
    this.name = 'CoworkingViewError';
    this.status = fields.status ?? 0;
    this.code = fields.code ?? 'ERROR';
    this.title = fields.title ?? '';
    this.detail = fields.detail ?? message;
  }
}

export function buildRatesUrl(options = {}) {
  const url = new URL(options.url || DEFAULT_URL);
  const locale = options.locale === undefined ? 'en' : options.locale;
  setParam(url.searchParams, 'locale', locale);
  setParam(url.searchParams, 'city', options.city);
  setParam(url.searchParams, 'country', options.country);
  setParam(url.searchParams, 'currency', options.currency);
  return url.toString();
}

function setParam(params, key, value) {
  if (value === undefined || value === null || value === '') {
    params.delete(key);
    return;
  }
  params.set(key, String(value));
}

export function retryWaitMs(headers, now = Date.now()) {
  const retryAfter = headerValue(headers, 'retry-after');
  const reset = headerValue(headers, 'ratelimit-reset');
  const wait = delayMs(retryAfter, now) ?? delayMs(reset, now) ?? FALLBACK_WAIT_MS;
  return Math.min(Math.max(wait, 0), MAX_WAIT_MS);
}

function headerValue(headers, name) {
  if (!headers || typeof headers.get !== 'function') return null;
  const value = headers.get(name);
  return value == null ? null : value;
}

function delayMs(value, now) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text) return null;
  if (/^-?\d+(?:\.\d+)?$/.test(text)) return Math.max(0, Number(text) * 1000);
  const moment = Date.parse(text);
  if (Number.isNaN(moment)) return null;
  return Math.max(0, moment - now);
}

function timeoutSignal(ms) {
  if (typeof AbortSignal !== 'undefined' && typeof AbortSignal.timeout === 'function') {
    return AbortSignal.timeout(ms);
  }
  const controller = new AbortController();
  setTimeout(() => controller.abort(), ms);
  return controller.signal;
}

function requestHeaders(userAgent) {
  const headers = new Headers({ Accept: 'application/json' });
  try {
    headers.set('User-Agent', userAgent || USER_AGENT);
  } catch {
    // Browsers forbid setting User-Agent from script.
  }
  return headers;
}

export async function fetchRates(options = {}) {
  const fetcher = options.fetch ?? globalThis.fetch;
  if (typeof fetcher !== 'function') {
    throw new CoworkingViewError('fetch is not available', { code: 'CONNECTION', status: 0 });
  }
  const sleeper = options.sleep ?? ((ms) => new Promise((resolve) => {
    setTimeout(resolve, ms);
  }));
  const url = buildRatesUrl(options);
  const headers = requestHeaders(options.userAgent);
  let attempt = 0;
  while (attempt < 2) {
    attempt += 1;
    let response;
    try {
      response = await fetcher(url, {
        method: 'GET',
        headers,
        signal: timeoutSignal(options.timeoutMs ?? TIMEOUT_MS),
      });
    } catch (error) {
      const name = error && error.name;
      const code = name === 'TimeoutError' || name === 'AbortError' ? 'TIMEOUT' : 'CONNECTION';
      const message = error && error.message ? error.message : 'request failed';
      throw new CoworkingViewError(`Could not reach the CoworkingView API: ${message}`, {
        code,
        status: 0,
      });
    }
    if (response.ok) return parsePayload(response, url);
    const retryable = attempt === 1 && (response.status === 429 || (response.status >= 500 && response.status <= 599));
    if (!retryable) throw await problemError(response);
    await sleeper(retryWaitMs(response.headers));
  }
  throw new CoworkingViewError('The CoworkingView API did not respond', { code: 'CONNECTION', status: 0 });
}

async function parsePayload(response, url) {
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new CoworkingViewError('The API returned a body that is not valid JSON', {
      status: response.status,
      code: 'BAD_RESPONSE',
      detail: `GET ${url}`,
    });
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) ||
    !payload.data || typeof payload.data !== 'object' || Array.isArray(payload.data)) {
    throw new CoworkingViewError('The API returned a body that is not the rates document', {
      status: response.status,
      code: 'BAD_RESPONSE',
      detail: `GET ${url}`,
    });
  }
  return payload;
}

async function problemError(response) {
  const text = await response.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    body = null;
  }
  const record = body && typeof body === 'object' ? body : {};
  const code = typeof record.code === 'string' && record.code ? record.code : `HTTP_${response.status}`;
  const title = typeof record.title === 'string' ? record.title : '';
  const detail = typeof record.detail === 'string' && record.detail
    ? record.detail
    : (response.statusText || `HTTP ${response.status}`);
  return new CoworkingViewError(detail || title || `HTTP ${response.status}`, {
    status: response.status,
    code,
    title,
    detail,
  });
}
