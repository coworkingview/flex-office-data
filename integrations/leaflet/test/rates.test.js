import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  CoworkingViewError,
  DEFAULT_URL,
  USER_AGENT,
  fetchRates,
} from '../src/rates.js';

const payload = {
  data: {
    cities: [],
    attribution: 'Source: CoworkingView Price Index',
    license: 'CC-BY-4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    asOf: '2026-11-03T00:00:00.000Z',
  },
  meta: { contractVersion: '1.0.0' },
};

function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

describe('fetchRates', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('requests the rates endpoint with Accept and does not call the network until asked', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(payload));
    await fetchRates({ fetch: fetchMock, sleep: async () => {} });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(`${DEFAULT_URL}?locale=en`);
    expect(init.method).toBe('GET');
    expect(init.headers.get('Accept')).toBe('application/json');
    expect(init.headers.get('User-Agent')).toBe(USER_AGENT);
  });

  it('sends locale, city, country and currency and drops empty filters', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(payload));
    await fetchRates({
      fetch: fetchMock,
      sleep: async () => {},
      locale: 'de',
      city: 'berlin',
      country: 'DE',
      currency: 'EUR',
    });
    const url = new URL(fetchMock.mock.calls[0][0]);
    expect(url.origin + url.pathname).toBe(DEFAULT_URL);
    expect(url.searchParams.get('locale')).toBe('de');
    expect(url.searchParams.get('city')).toBe('berlin');
    expect(url.searchParams.get('country')).toBe('DE');
    expect(url.searchParams.get('currency')).toBe('EUR');

    fetchMock.mockClear();
    await fetchRates({ fetch: fetchMock, sleep: async () => {}, city: '', country: null });
    const again = new URL(fetchMock.mock.calls[0][0]);
    expect(again.searchParams.get('locale')).toBe('en');
    expect(again.searchParams.has('city')).toBe(false);
    expect(again.searchParams.has('country')).toBe(false);
  });

  it('retries once on 429 using Retry-After, capped at 10 seconds', async () => {
    const waits = [];
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse({ title: 'Slow', detail: 'slow', code: 'RATE_LIMIT' }, 429, { 'Retry-After': '30' }))
      .mockResolvedValueOnce(jsonResponse(payload));
    const result = await fetchRates({
      fetch: fetchMock,
      sleep: async (ms) => { waits.push(ms); },
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(waits).toEqual([10000]);
    expect(result.data.attribution).toBe(payload.data.attribution);
  });

  it('uses RateLimit-Reset when Retry-After is absent, else 2 seconds', async () => {
    const waits = [];
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse({}, 503, { 'RateLimit-Reset': '3' }))
      .mockResolvedValueOnce(jsonResponse(payload));
    await fetchRates({ fetch: fetchMock, sleep: async (ms) => { waits.push(ms); } });
    expect(waits).toEqual([3000]);

    waits.length = 0;
    fetchMock.mockReset();
    fetchMock
      .mockResolvedValueOnce(jsonResponse({}, 500))
      .mockResolvedValueOnce(jsonResponse(payload));
    await fetchRates({ fetch: fetchMock, sleep: async (ms) => { waits.push(ms); } });
    expect(waits).toEqual([2000]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not retry a 400 problem response', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({
      type: 'about:blank',
      title: 'Bad currency',
      status: 400,
      code: 'VALIDATION',
      detail: 'currency is not supported',
    }, 400));
    const sleep = vi.fn(async () => {});
    await expect(fetchRates({ fetch: fetchMock, sleep })).rejects.toMatchObject({
      name: 'CoworkingViewError',
      status: 400,
      code: 'VALIDATION',
      title: 'Bad currency',
      detail: 'currency is not supported',
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it('reports a non-JSON body as BAD_RESPONSE and does not retry it', async () => {
    const fetchMock = vi.fn(async () => new Response('not-json', { status: 200 }));
    await expect(fetchRates({ fetch: fetchMock, sleep: async () => {} })).rejects.toMatchObject({
      code: 'BAD_RESPONSE',
      status: 200,
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('uses HTTP_status when the problem body has no code', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ title: 'Missing', detail: 'gone' }, 404));
    await expect(fetchRates({ fetch: fetchMock, sleep: async () => {} })).rejects.toMatchObject({
      status: 404,
      code: 'HTTP_404',
      detail: 'gone',
    });
  });

  it('does not retry a connection failure', async () => {
    const fetchMock = vi.fn(async () => { throw new TypeError('network down'); });
    await expect(fetchRates({ fetch: fetchMock, sleep: async () => {} })).rejects.toBeInstanceOf(CoworkingViewError);
    await expect(fetchRates({ fetch: fetchMock, sleep: async () => {} })).rejects.toMatchObject({
      code: 'CONNECTION',
      status: 0,
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
