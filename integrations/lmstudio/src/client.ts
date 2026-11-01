/**
 * One GET against https://api.coworkingview.com. No other host is requested.
 * On 429 or 5xx the client waits and retries once, matching spec/SPEC.md section 2.
 */

import { API_ORIGIN, PAGE_SIZE } from "./parse";

export const USER_AGENT =
  "lmstudio-plugin-coworkingview-workspace-prices/1.0.0 (+https://github.com/coworkingview/flex-office-data)";

const MAX_BODY_BYTES = 5 * 1024 * 1024;
const FALLBACK_WAIT_SECONDS = 2;
const MAX_WAIT_SECONDS = 10;

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly title: string;
  readonly detail: string;

  constructor(status: number, code: string, title: string, detail: string) {
    super(detail || title);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.title = title;
    this.detail = detail;
  }
}

export type HttpResponse = {
  status: number;
  statusText: string;
  headers: Record<string, string>;
  body: string;
};

export type GetFn = (
  url: string,
  init: { headers: Record<string, string>; signal: AbortSignal },
) => Promise<HttpResponse>;

export type SleepFn = (ms: number, signal: AbortSignal) => Promise<void>;

export class CoworkingViewClient {
  constructor(
    private readonly options: {
      timeoutMs: number;
      get?: GetFn;
      sleep?: SleepFn;
    },
  ) {}

  rates(locale: string, city: string | null, signal?: AbortSignal): Promise<unknown> {
    const params = new URLSearchParams({ locale });
    if (city !== null) {
      params.set("city", city);
    }
    return this.get("/v1/market/rates", params, signal);
  }

  properties(
    locale: string,
    city: string,
    product: string | null,
    signal?: AbortSignal,
  ): Promise<unknown> {
    const params = new URLSearchParams({
      locale,
      city,
      page: "1",
      pageSize: String(PAGE_SIZE),
      sortBy: "date-desc",
    });
    if (product !== null) {
      params.set("pricingOptionType", product);
    }
    return this.get("/v1/properties", params, signal);
  }

  private async get(path: string, params: URLSearchParams, caller?: AbortSignal): Promise<unknown> {
    const url = new URL(path, API_ORIGIN);
    url.search = params.toString();
    if (url.origin !== API_ORIGIN) {
      throw new ApiError(0, "BAD_URL", "Refusing to call a host other than the CoworkingView API", url.origin);
    }

    const headers = {
      Accept: "application/json",
      "User-Agent": USER_AGENT,
    };
    const get = this.options.get ?? defaultGet;
    const sleep = this.options.sleep ?? delay;

    let response = await this.once(get, url.toString(), headers, caller);
    if (response.status === 429 || (response.status >= 500 && response.status <= 599)) {
      const waitSignal = caller
        ? AbortSignal.any([caller, AbortSignal.timeout(this.options.timeoutMs)])
        : AbortSignal.timeout(this.options.timeoutMs);
      try {
        await sleep(retryWaitMs(response.headers), waitSignal);
      } catch (error) {
        if (caller?.aborted) {
          throw error;
        }
        throw new ApiError(0, "TIMEOUT", "The CoworkingView API did not respond in time", API_ORIGIN);
      }
      response = await this.once(get, url.toString(), headers, caller);
    }
    if (response.status < 200 || response.status > 299) {
      throw problem(response);
    }
    return parseJson(response);
  }

  private async once(
    get: GetFn,
    url: string,
    headers: Record<string, string>,
    caller?: AbortSignal,
  ): Promise<HttpResponse> {
    const timed = AbortSignal.timeout(this.options.timeoutMs);
    const signal = caller ? AbortSignal.any([caller, timed]) : timed;
    try {
      return await get(url, { headers, signal });
    } catch (error) {
      if (caller?.aborted) {
        throw error;
      }
      if (timed.aborted) {
        throw new ApiError(0, "TIMEOUT", "The CoworkingView API did not respond in time", API_ORIGIN);
      }
      throw new ApiError(0, "CONNECTION", "Could not reach the CoworkingView API", API_ORIGIN);
    }
  }
}

export function retryWaitMs(headers: Record<string, string>, now = Date.now()): number {
  const lowered = lowerHeaders(headers);
  let seconds = parseDelay(lowered["retry-after"], true, now);
  if (seconds === null) {
    seconds = parseDelay(lowered["ratelimit-reset"], false, now);
  }
  if (seconds === null) {
    seconds = FALLBACK_WAIT_SECONDS;
  }
  return Math.round(Math.min(Math.max(seconds, 0), MAX_WAIT_SECONDS) * 1000);
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 0) {
      return `Error: ${error.detail || error.title}`;
    }
    const text = error.detail || error.title;
    return `Error: CoworkingView API ${error.status} ${error.code}: ${text}`;
  }
  return "Error: The CoworkingView API request failed.";
}

function parseJson(response: HttpResponse): unknown {
  if (response.body.length > MAX_BODY_BYTES) {
    throw new ApiError(response.status, "BAD_RESPONSE", "The API response is too large", "");
  }
  try {
    const payload: unknown = JSON.parse(response.body);
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      throw new ApiError(response.status, "BAD_RESPONSE", "The API returned JSON that is not an object", "");
    }
    return payload;
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    throw new ApiError(response.status, "BAD_RESPONSE", "The API returned a body that is not valid JSON", "");
  }
}

function problem(response: HttpResponse): ApiError {
  let parsed: Record<string, unknown> | null = null;
  try {
    const value: unknown = JSON.parse(response.body);
    if (value && typeof value === "object" && !Array.isArray(value)) {
      parsed = value as Record<string, unknown>;
    }
  } catch {
    parsed = null;
  }
  const code =
    parsed && typeof parsed.code === "string" && parsed.code ? parsed.code : `HTTP_${response.status}`;
  const title =
    parsed && typeof parsed.title === "string" && parsed.title
      ? parsed.title
      : response.statusText || `HTTP ${response.status}`;
  const detail = parsed && typeof parsed.detail === "string" ? parsed.detail : "";
  return new ApiError(response.status, code, title, detail);
}

function lowerHeaders(headers: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    out[key.toLowerCase()] = value;
  }
  return out;
}

function parseDelay(value: string | undefined, allowDate: boolean, now: number): number | null {
  if (value === undefined) {
    return null;
  }
  const text = value.trim();
  if (text.length === 0) {
    return null;
  }
  const numeric = Number(text);
  if (Number.isFinite(numeric)) {
    return Math.max(0, numeric);
  }
  if (!allowDate) {
    return null;
  }
  const when = Date.parse(text);
  if (Number.isNaN(when)) {
    return null;
  }
  return Math.max(0, (when - now) / 1000);
}

function delay(ms: number, signal: AbortSignal): Promise<void> {
  if (ms <= 0) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(signal.reason instanceof Error ? signal.reason : new DOMException("Aborted", "AbortError"));
      return;
    }
    const timer = setTimeout(resolve, ms);
    signal.addEventListener(
      "abort",
      () => {
        clearTimeout(timer);
        reject(signal.reason instanceof Error ? signal.reason : new DOMException("Aborted", "AbortError"));
      },
      { once: true },
    );
  });
}

async function defaultGet(
  url: string,
  init: { headers: Record<string, string>; signal: AbortSignal },
): Promise<HttpResponse> {
  const response = await fetch(url, {
    method: "GET",
    headers: init.headers,
    signal: init.signal,
    redirect: "error",
  });
  const body = await response.text();
  const headers: Record<string, string> = {};
  response.headers.forEach((value, key) => {
    headers[key.toLowerCase()] = value;
  });
  return {
    status: response.status,
    statusText: response.statusText,
    headers,
    body,
  };
}
