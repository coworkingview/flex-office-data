import { ApiError, CoworkingViewClient, PLUGIN_VERSION, RawResponse, RequestFn, USER_AGENT } from '../src/client';
import { retryWaitSeconds } from '../src/retry';

function response(status: number, body: string, headers: Record<string, string> = {}): RawResponse {
	return { status, statusText: 'STATUS', headers, body };
}

describe('retry wait', () => {
	test('uses Retry-After, then RateLimit-Reset, then 2 seconds, capped at 10', () => {
		expect(retryWaitSeconds({ 'retry-after': '3' })).toBe(3);
		expect(retryWaitSeconds({ 'retry-after': '50' })).toBe(10);
		expect(retryWaitSeconds({ 'ratelimit-reset': '4' })).toBe(4);
		expect(retryWaitSeconds({})).toBe(2);
		const soon = new Date(Date.now() + 1500).toUTCString();
		expect(retryWaitSeconds({ 'retry-after': soon })).toBeGreaterThan(0);
		expect(retryWaitSeconds({ 'retry-after': soon })).toBeLessThanOrEqual(10);
	});
});

describe('CoworkingViewClient', () => {
	test('sends the public user agent and does not retry a success', async () => {
		const calls: string[][] = [];
		const request: RequestFn = async (url, headers) => {
			calls.push([url, headers.Accept, headers['User-Agent']]);
			return response(200, JSON.stringify({ data: [] }));
		};
		const client = new CoworkingViewClient('https://api.coworkingview.com', request, async () => undefined);
		await client.properties('berlin');
		expect(calls).toEqual([[
			'https://api.coworkingview.com/v1/properties?locale=en&city=berlin&page=1&pageSize=20&sortBy=date-desc',
			'application/json',
			USER_AGENT,
		]]);
		expect(USER_AGENT).toBe(`joplin-plugin-coworkingview/${PLUGIN_VERSION} (+https://github.com/coworkingview/flex-office-data)`);
	});

	test('retries a 429 once and then reads the JSON object', async () => {
		const bodies = [
			response(429, '', { 'retry-after': '0' }),
			response(200, JSON.stringify({ data: { cities: [] } })),
		];
		let sleeps = 0;
		const request: RequestFn = async () => {
			const next = bodies.shift();
			if (!next) throw new Error('unexpected extra request');
			return next;
		};
		const client = new CoworkingViewClient('https://api.coworkingview.com', request, async () => {
			sleeps += 1;
		});
		await expect(client.rates('berlin')).resolves.toEqual({ data: { cities: [] } });
		expect(sleeps).toBe(1);
		expect(bodies).toHaveLength(0);
	});

	test('does not retry a 400 and surfaces the problem detail', async () => {
		let calls = 0;
		const request: RequestFn = async () => {
			calls += 1;
			return response(400, JSON.stringify({
				title: 'Bad Request',
				status: 400,
				code: 'VALIDATION',
				detail: 'Unknown city.',
			}));
		};
		const client = new CoworkingViewClient('https://api.coworkingview.com', request, async () => undefined);
		await expect(client.rates(null)).rejects.toMatchObject({
			status: 400,
			code: 'VALIDATION',
			message: 'Unknown city.',
		});
		expect(calls).toBe(1);
	});

	test('gives up after the single 5xx retry', async () => {
		let calls = 0;
		const request: RequestFn = async () => {
			calls += 1;
			return response(503, 'nope');
		};
		const client = new CoworkingViewClient('https://api.coworkingview.com', request, async () => undefined);
		await expect(client.properties('berlin')).rejects.toBeInstanceOf(ApiError);
		expect(calls).toBe(2);
	});

	test('rejects a 200 that is not a JSON object', async () => {
		const request: RequestFn = async () => response(200, '[1, 2]');
		const client = new CoworkingViewClient('https://api.coworkingview.com', request, async () => undefined);
		await expect(client.properties('berlin')).rejects.toMatchObject({ code: 'BAD_RESPONSE' });
	});
});
