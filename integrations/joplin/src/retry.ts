/** One wait before the single retry on HTTP 429 or 5xx (SPEC section 2). */

export const FALLBACK_WAIT = 2;
export const MAX_WAIT = 10;

export function retryWaitSeconds(headers: Record<string, string>, now = Date.now()): number {
	const retryAfter = header(headers, 'retry-after');
	const rateLimitReset = header(headers, 'ratelimit-reset');
	const wait = parseDelay(retryAfter, now) ?? parseDelay(rateLimitReset, now) ?? FALLBACK_WAIT;
	return Math.min(Math.max(wait, 0), MAX_WAIT);
}

export function isRetryableStatus(status: number): boolean {
	return status === 429 || (status >= 500 && status <= 599);
}

function header(headers: Record<string, string>, name: string): string | undefined {
	const value = headers[name] ?? headers[name.toLowerCase()];
	if (typeof value !== 'string') return undefined;
	const trimmed = value.trim();
	return trimmed ? trimmed : undefined;
}

function parseDelay(value: string | undefined, now: number): number | null {
	if (value === undefined) return null;
	const numeric = Number(value);
	if (Number.isFinite(numeric)) return Math.max(0, numeric);
	const parsed = Date.parse(value);
	if (Number.isNaN(parsed)) return null;
	return Math.max(0, (parsed - now) / 1000);
}
