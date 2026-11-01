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

import { CoworkingViewApiError, loadCity, PUBLIC_API, ratesUrl, spacesUrl } from './api';
import errorValidation from './fixtures/error_validation.json';
import marketRates from './fixtures/market_rates.json';
import propertiesBerlin from './fixtures/properties_berlin.json';

const sleep = jest.fn(async () => undefined);

function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

describe('loadCity', () => {
  beforeEach(() => {
    sleep.mockClear();
  });

  it('requests the public rates and properties endpoints once each', async () => {
    const fetchImpl = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      expect(new URL(url).host).toBe('api.coworkingview.com');
      if (url.includes('/v1/market/rates')) {
        return jsonResponse(marketRates);
      }
      if (url.includes('/v1/properties')) {
        return jsonResponse(propertiesBerlin);
      }
      throw new Error(`unexpected url ${url}`);
    });

    const snapshot = await loadCity('Berlin', { fetchImpl, sleep });

    expect(snapshot.city).toBe('berlin');
    expect(snapshot.rates.rows[0].median).toBe(214);
    expect(snapshot.spaces.rows).toHaveLength(3);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    const urls = fetchImpl.mock.calls.map(call => String(call[0]));
    expect(urls).toContain(ratesUrl(PUBLIC_API, 'berlin'));
    expect(urls).toContain(spacesUrl(PUBLIC_API, 'berlin'));
    expect(spacesUrl(PUBLIC_API, 'berlin')).toContain('pageSize=10');
    expect(sleep).not.toHaveBeenCalled();
  });

  it('joins a proxy base URL without dropping the mount path', () => {
    const base = 'http://localhost:7007/api/proxy/coworkingview';
    expect(ratesUrl(base, 'berlin')).toBe(
      'http://localhost:7007/api/proxy/coworkingview/v1/market/rates?locale=en&city=berlin',
    );
  });

  it('does not call the network for a slug the API would not accept', async () => {
    const fetchImpl = jest.fn();
    await expect(loadCity('Berlin!', { fetchImpl, sleep })).rejects.toBeInstanceOf(CoworkingViewApiError);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('retries each request once after HTTP 429 or 500, then reads the body', async () => {
    const attempts = new Map<string, number>();
    const fetchImpl = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      const count = (attempts.get(url) ?? 0) + 1;
      attempts.set(url, count);
      if (count === 1) {
        const status = url.includes('/v1/market/rates') ? 429 : 500;
        return jsonResponse({ code: `HTTP_${status}` }, status, { 'retry-after': '2' });
      }
      if (url.includes('/v1/market/rates')) {
        return jsonResponse(marketRates);
      }
      return jsonResponse(propertiesBerlin);
    });

    const snapshot = await loadCity('berlin', { fetchImpl, sleep });

    expect(snapshot.rates.rows[0].median).toBe(214);
    expect(snapshot.spaces.total).toBe(110);
    expect(attempts.get(ratesUrl(PUBLIC_API, 'berlin'))).toBe(2);
    expect(attempts.get(spacesUrl(PUBLIC_API, 'berlin'))).toBe(2);
    expect(sleep).toHaveBeenCalledWith(2000);
  });

  it('surfaces a problem body and does not retry HTTP 400', async () => {
    const fetchImpl = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/v1/market/rates')) {
        return jsonResponse(marketRates);
      }
      return jsonResponse(errorValidation, 400);
    });

    await expect(loadCity('berlin', { fetchImpl, sleep })).rejects.toMatchObject({
      status: 400,
      code: 'VALIDATION_FAILED',
      detail: errorValidation.detail,
    });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(sleep).not.toHaveBeenCalled();
  });
});
