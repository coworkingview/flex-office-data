/**
 * HTTPS calls to the public CoworkingView API. No API key.
 *
 * A 429 or 5xx is retried once. The wait is Retry-After, otherwise
 * RateLimit-Reset, otherwise 2 seconds, and never more than 10 seconds.
 * The browser sets User-Agent; an extension page cannot replace that header.
 */

import { ApiError } from "./errors.js";
import {
  API_ORIGIN,
  isSlug,
  parseCities,
  parseCityRates,
  parseWorkspaceCount,
  uiLocale,
} from "./parse.js";

export { ApiError };

export function buildRatesUrl(locale, city) {
  const url = new URL("/v1/market/rates", API_ORIGIN);
  url.searchParams.set("locale", normalizeLocale(locale));
  if (city) {
    url.searchParams.set("city", city);
  }
  return url.toString();
}

export function buildPropertiesUrl(locale, city) {
  const url = new URL("/v1/properties", API_ORIGIN);
  url.searchParams.set("locale", normalizeLocale(locale));
  url.searchParams.set("city", city);
  url.searchParams.set("page", "1");
  url.searchParams.set("pageSize", "1");
  return url.toString();
}

/** Seconds from a response header, or null when the header is absent or not a number. */
export function retryDelayMs(headers) {
  const retryAfter = headerSeconds(headers, "retry-after");
  const reset = headerSeconds(headers, "ratelimit-reset");
  let seconds = retryAfter ?? reset ?? 2;
  if (seconds > 10) {
    seconds = 10;
  }
  if (seconds < 0) {
    seconds = 0;
  }
  return seconds * 1000;
}

export async function fetchJson(url, options = {}) {
  const fetchImpl = options.fetchImpl ?? globalThis.fetch;
  const sleep = options.sleep ?? delay;
  let response = await send(fetchImpl, url);
  if (shouldRetry(response.status)) {
    await sleep(retryDelayMs(response.headers));
    response = await send(fetchImpl, url);
  }
  const body = await readJson(response);
  if (!response.ok) {
    const problem = parseProblem(body, response.status);
    const message = problem.detail || problem.title || `HTTP ${response.status}`;
    throw new ApiError(message, problem);
  }
  return body;
}

/**
 * Prices for one city, plus the catalogue total.
 * The rates request always includes city=. The properties request asks for
 * one row so pagination.total is present; that row is discarded by the parser.
 * A properties failure still returns the price table.
 */
export async function loadReport(city, locale, options = {}) {
  if (!isSlug(city)) {
    throw new ApiError("Invalid city slug", { code: "BAD_CITY" });
  }
  const ratesPromise = fetchJson(buildRatesUrl(locale, city), options);
  const propertiesPromise = fetchJson(buildPropertiesUrl(locale, city), options).then(
    (body) => ({ ok: true, body }),
    (error) => ({ ok: false, error }),
  );
  const ratesBody = await ratesPromise;
  const rates = parseCityRates(ratesBody, city);
  if (!rates) {
    throw new ApiError("Unknown city", { code: "UNKNOWN_CITY" });
  }
  const properties = await propertiesPromise;

  let workspaceTotal = null;
  let citation = null;
  let citationUrl = null;
  let workspaceError = null;
  if (properties.ok) {
    const count = parseWorkspaceCount(properties.body);
    if (count) {
      workspaceTotal = count.total;
      citation = count.citation;
      citationUrl = count.citationUrl;
    } else {
      workspaceError = new ApiError("pagination.total is missing", { code: "BAD_RESPONSE" });
    }
  } else {
    workspaceError = properties.error;
  }

  return {
    ...rates,
    workspaceTotal,
    citation,
    citationUrl,
    workspaceError,
  };
}

/** Published cities for the selector. GET /v1/market/rates?locale= with no city. */
export async function loadCities(locale, options = {}) {
  const body = await fetchJson(buildRatesUrl(locale), options);
  return parseCities(body);
}

function normalizeLocale(locale) {
  return uiLocale(locale);
}

function shouldRetry(status) {
  return status === 429 || (status >= 500 && status <= 599);
}

function headerSeconds(headers, name) {
  if (!headers || typeof headers.get !== "function") {
    return null;
  }
  const raw = headers.get(name);
  if (raw == null || raw === "") {
    return null;
  }
  const value = Number(raw);
  if (!Number.isFinite(value)) {
    return null;
  }
  return value;
}

async function send(fetchImpl, url) {
  const init = {
    method: "GET",
    headers: { Accept: "application/json" },
    credentials: "omit",
    cache: "default",
    redirect: "follow",
  };
  if (typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function") {
    init.signal = AbortSignal.timeout(20000);
  }
  return fetchImpl(url, init);
}

async function readJson(response) {
  const text = await response.text();
  if (!text) {
    throw new ApiError("Empty response", { status: response.status, code: "BAD_RESPONSE" });
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError("Response was not JSON", {
      status: response.status,
      code: "BAD_RESPONSE",
    });
  }
}

export function parseProblem(body, status) {
  const record = body && typeof body === "object" && !Array.isArray(body) ? body : null;
  const code = record && typeof record.code === "string" ? record.code : `HTTP_${status}`;
  const title = record && typeof record.title === "string" ? record.title : "";
  const detail = record && typeof record.detail === "string" ? record.detail : title;
  return { status, code, title, detail };
}

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
