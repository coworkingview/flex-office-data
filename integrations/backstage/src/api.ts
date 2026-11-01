/*
 * Copyright 2026 CoworkingView
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { isCitySlug, parseRates, parseSpaces } from './parse';
import { CitySnapshot } from './types';

export const PUBLIC_API = 'https://api.coworkingview.com';
export const PAGE_SIZE = 10;

const USER_AGENT =
  'coworkingview-backstage/0.1.0 (+https://github.com/coworkingview/flex-office-data)';

const TIMEOUT_MS = 20_000;

export class CoworkingViewApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly title: string | null;
  readonly detail: string | null;

  constructor(status: number, code: string, title: string | null, detail: string | null) {
    super(detail && detail.length > 0 ? detail : code);
    this.name = 'CoworkingViewApiError';
    this.status = status;
    this.code = code;
    this.title = title;
    this.detail = detail;
  }
}

export type ClientOptions = {
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
};

/** Price Index and one page of spaces for a city slug. No further pages are requested. */
export async function loadCity(city: string, options: ClientOptions = {}): Promise<CitySnapshot> {
  const slug = city.trim().toLowerCase();
  if (!isCitySlug(slug)) {
    throw new CoworkingViewApiError(
      0,
      'BAD_CITY',
      null,
      'Enter a city slug such as berlin.',
    );
  }
  const baseUrl = resolveBase(options.baseUrl);
  const fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  const sleep = options.sleep ?? defaultSleep;
  const [ratesBody, spacesBody] = await Promise.all([
    getJson(ratesUrl(baseUrl, slug), fetchImpl, sleep),
    getJson(spacesUrl(baseUrl, slug), fetchImpl, sleep),
  ]);
  return {
    city: slug,
    rates: parseRates(ratesBody, slug),
    spaces: parseSpaces(spacesBody, 'en'),
  };
}

export function ratesUrl(baseUrl: string, city: string): string {
  const url = new URL(`${baseUrl}/v1/market/rates`);
  url.searchParams.set('locale', 'en');
  url.searchParams.set('city', city);
  return url.toString();
}

export function spacesUrl(baseUrl: string, city: string): string {
  const url = new URL(`${baseUrl}/v1/properties`);
  url.searchParams.set('locale', 'en');
  url.searchParams.set('city', city);
  url.searchParams.set('page', '1');
  url.searchParams.set('pageSize', String(PAGE_SIZE));
  return url.toString();
}

function resolveBase(baseUrl: string | undefined): string {
  const value = (baseUrl ?? PUBLIC_API).trim().replace(/\/$/, '');
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new CoworkingViewApiError(0, 'BAD_BASE_URL', null, 'coworkingview.baseUrl is not a URL.');
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new CoworkingViewApiError(
      0,
      'BAD_BASE_URL',
      null,
      'coworkingview.baseUrl must use http or https.',
    );
  }
  return value;
}

async function getJson(
  url: string,
  fetchImpl: typeof fetch,
  sleep: (ms: number) => Promise<void>,
): Promise<unknown> {
  let response: Response | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      response = await fetchImpl(url, {
        headers: {
          Accept: 'application/json',
          'User-Agent': USER_AGENT,
        },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Request failed';
      throw new CoworkingViewApiError(
        0,
        'NETWORK',
        null,
        `${message}. If the browser blocked the call, set coworkingview.baseUrl to the Backstage proxy path.`,
      );
    }

    if ((response.status === 429 || response.status >= 500) && attempt === 0) {
      await sleep(retryDelayMs(response));
      continue;
    }
    break;
  }

  if (!response) {
    throw new CoworkingViewApiError(0, 'HTTP_RETRY', null, 'HTTP_RETRY');
  }

  const text = await response.text();
  let body: unknown;
  try {
    body = JSON.parse(text) as unknown;
  } catch {
    throw new CoworkingViewApiError(response.status, 'BAD_RESPONSE', null, 'The response was not JSON.');
  }

  if (!response.ok) {
    const problem = asRecord(body);
    const code = typeof problem?.code === 'string' ? problem.code : `HTTP_${response.status}`;
    const title = typeof problem?.title === 'string' ? problem.title : null;
    const detail = typeof problem?.detail === 'string' ? problem.detail : null;
    throw new CoworkingViewApiError(response.status, code, title, detail);
  }
  return body;
}

function retryDelayMs(response: Response): number {
  const retryAfter = Number(response.headers.get('retry-after'));
  const reset = Number(response.headers.get('ratelimit-reset'));
  let seconds = 2;
  if (Number.isFinite(retryAfter) && retryAfter >= 0) {
    seconds = retryAfter;
  } else if (Number.isFinite(reset) && reset >= 0) {
    seconds = reset;
  }
  return Math.min(seconds, 10) * 1000;
}

function defaultSleep(ms: number): Promise<void> {
  return new Promise(resolve => {
    setTimeout(resolve, ms);
  });
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}
