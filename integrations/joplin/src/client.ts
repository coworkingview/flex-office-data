/**
 * Read-only client for the public CoworkingView API.
 *
 * Endpoints, matching the other clients in this repository:
 * `GET /v1/properties` and `GET /v1/market/rates`.
 * Nothing is requested until a command calls one of those.
 */

import * as http from 'http';
import * as https from 'https';

import { propertiesUrl, ratesUrl } from './format';
import { isRetryableStatus, retryWaitSeconds } from './retry';

export const PLUGIN_VERSION = '1.0.0';
export const USER_AGENT = `joplin-plugin-coworkingview/${PLUGIN_VERSION} (+https://github.com/coworkingview/flex-office-data)`;
export const TIMEOUT_MS = 20000;
const MAX_BODY_BYTES = 5 * 1024 * 1024;

export class ApiError extends Error {
	readonly status: number;
	readonly code: string;

	constructor(status: number, code: string, title: string, detail: string) {
		super(detail || title);
		this.name = 'ApiError';
		this.status = status;
		this.code = code;
	}
}

export interface RawResponse {
	status: number;
	statusText: string;
	headers: Record<string, string>;
	body: string;
}

export type RequestFn = (
	url: string,
	headers: Record<string, string>,
	timeoutMs: number,
) => Promise<RawResponse>;

export class CoworkingViewClient {
	constructor(
		private readonly baseUrl: string,
		private readonly request: RequestFn = nodeRequest,
		private readonly sleep: (seconds: number) => Promise<void> = delay,
	) {}

	properties(city: string): Promise<unknown> {
		return this.get(propertiesUrl(this.baseUrl, city));
	}

	rates(city: string | null): Promise<unknown> {
		return this.get(ratesUrl(this.baseUrl, city));
	}

	private async get(url: string): Promise<unknown> {
		const headers = {
			Accept: 'application/json',
			'User-Agent': USER_AGENT,
		};
		let response = await this.request(url, headers, TIMEOUT_MS);
		if (isRetryableStatus(response.status)) {
			await this.sleep(retryWaitSeconds(response.headers));
			response = await this.request(url, headers, TIMEOUT_MS);
		}
		if (response.status < 200 || response.status > 299) {
			throw problem(response);
		}
		let payload: unknown;
		try {
			payload = JSON.parse(response.body);
		} catch {
			throw new ApiError(response.status, 'BAD_RESPONSE', 'The API returned a body that is not valid JSON', '');
		}
		if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
			throw new ApiError(response.status, 'BAD_RESPONSE', 'The API returned JSON that is not an object', '');
		}
		return payload;
	}
}

function problem(response: RawResponse): ApiError {
	let parsed: Record<string, unknown> | null = null;
	try {
		const value = JSON.parse(response.body) as unknown;
		if (value && typeof value === 'object' && !Array.isArray(value)) parsed = value as Record<string, unknown>;
	} catch {
		parsed = null;
	}
	const code = parsed && typeof parsed.code === 'string' && parsed.code ? parsed.code : `HTTP_${response.status}`;
	const title = parsed && typeof parsed.title === 'string' && parsed.title
		? parsed.title
		: (response.statusText || `HTTP ${response.status}`);
	const detail = parsed && typeof parsed.detail === 'string' ? parsed.detail : '';
	return new ApiError(response.status, code, title, detail);
}

function delay(seconds: number): Promise<void> {
	return new Promise(resolve => {
		setTimeout(resolve, seconds * 1000);
	});
}

export function nodeRequest(urlString: string, headers: Record<string, string>, timeoutMs: number): Promise<RawResponse> {
	return requestOnce(urlString, headers, timeoutMs, 3);
}

function requestOnce(
	urlString: string,
	headers: Record<string, string>,
	timeoutMs: number,
	redirectsLeft: number,
): Promise<RawResponse> {
	return new Promise((resolve, reject) => {
		let url: URL;
		try {
			url = new URL(urlString);
		} catch {
			reject(new ApiError(0, 'BAD_URL', 'The request URL is not valid', urlString));
			return;
		}
		if (url.protocol !== 'https:' && url.protocol !== 'http:') {
			reject(new ApiError(0, 'BAD_URL', 'The request URL is not http or https', urlString));
			return;
		}
		const lib = url.protocol === 'https:' ? https : http;
		const req = lib.request(url, { method: 'GET', headers, timeout: timeoutMs }, res => {
			const status = res.statusCode || 0;
			const location = res.headers.location;
			if (status >= 300 && status < 400 && location && redirectsLeft > 0) {
				res.resume();
				const next = new URL(location, url).toString();
				if (!next.startsWith('https:') && !next.startsWith('http:')) {
					reject(new ApiError(status, 'BAD_REDIRECT', 'The API redirected to a non-HTTP address', next));
					return;
				}
				requestOnce(next, headers, timeoutMs, redirectsLeft - 1).then(resolve, reject);
				return;
			}
			const chunks: Buffer[] = [];
			let received = 0;
			res.on('data', (chunk: Buffer) => {
				received += chunk.length;
				if (received > MAX_BODY_BYTES) {
					res.destroy();
					reject(new ApiError(status, 'BAD_RESPONSE', 'The API response is too large', ''));
					return;
				}
				chunks.push(chunk);
			});
			res.on('end', () => {
				const responseHeaders: Record<string, string> = {};
				for (const [key, value] of Object.entries(res.headers)) {
					if (typeof value === 'string') responseHeaders[key.toLowerCase()] = value;
					else if (Array.isArray(value) && value.length) responseHeaders[key.toLowerCase()] = value[0];
				}
				resolve({
					status,
					statusText: res.statusMessage || '',
					headers: responseHeaders,
					body: Buffer.concat(chunks).toString('utf8'),
				});
			});
			res.on('error', () => {
				reject(new ApiError(0, 'CONNECTION', 'Could not reach the CoworkingView API', url.origin));
			});
		});
		req.on('timeout', () => {
			req.destroy(new ApiError(0, 'TIMEOUT', 'The CoworkingView API did not respond in time', url.origin));
		});
		req.on('error', error => {
			if (error instanceof ApiError) {
				reject(error);
				return;
			}
			reject(new ApiError(0, 'CONNECTION', 'Could not reach the CoworkingView API', url.origin));
		});
		req.end();
	});
}
