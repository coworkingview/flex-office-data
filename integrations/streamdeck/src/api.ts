import {
	type CityOption,
	type MarketRate,
	parseCityOptions,
	parseMarketRate,
	parseWorkspaceCount,
	type WorkspaceCount,
} from "./parse.ts";
import { type FigureId, REFRESH_INTERVAL_MS } from "./settings.ts";

const USER_AGENT = "coworkingview-streamdeck/1.0.0 (+https://github.com/coworkingview/flex-office-data)";

type CacheEntry = {
	expiresAt: number;
	value: unknown;
};

const cache = new Map<string, CacheEntry>();
const inflight = new Map<string, Promise<unknown>>();
let logMessage: (message: string) => void = () => {};

/** Receives the Price Index attribution string when a rates response is fetched. */
export function setApiLogger(logger: (message: string) => void): void {
	logMessage = logger;
}

export async function fetchWorkspaceCount(city: string): Promise<WorkspaceCount> {
	const body = await cachedJson(propertiesUrl(city));
	const parsed = parseWorkspaceCount(body, city);
	if (!parsed) {
		throw new Error("BAD_RESPONSE properties");
	}
	return parsed;
}

export async function fetchMarketRate(city: string, figure: FigureId): Promise<MarketRate | null> {
	const body = await cachedJson(ratesUrl(city));
	return parseMarketRate(body, city, figure);
}

export async function fetchCityOptions(): Promise<CityOption[]> {
	const body = await cachedJson(ratesUrl(undefined));
	return parseCityOptions(body);
}

function apiBase(): string {
	const configured = process.env.COWORKINGVIEW_API_URL?.trim();
	if (configured && /^https?:\/\//.test(configured)) {
		return configured.replace(/\/$/, "");
	}
	return "https://api.coworkingview.com";
}

function ratesUrl(city: string | undefined): string {
	const url = new URL("/v1/market/rates", apiBase());
	url.searchParams.set("locale", "en");
	if (city) {
		url.searchParams.set("city", city);
	}
	return url.toString();
}

function propertiesUrl(city: string): string {
	const url = new URL("/v1/properties", apiBase());
	url.searchParams.set("locale", "en");
	url.searchParams.set("city", city);
	url.searchParams.set("page", "1");
	url.searchParams.set("pageSize", "1");
	return url.toString();
}

async function cachedJson(url: string): Promise<unknown> {
	const hit = cache.get(url);
	if (hit && hit.expiresAt > Date.now()) {
		return hit.value;
	}

	const pending = inflight.get(url);
	if (pending) {
		return pending;
	}

	const promise = fetchJson(url)
		.then((value) => {
			cache.set(url, { expiresAt: Date.now() + REFRESH_INTERVAL_MS, value });
			const attribution = readAttribution(value);
			if (attribution) {
				logMessage(attribution);
			}
			return value;
		})
		.finally(() => {
			inflight.delete(url);
		});

	inflight.set(url, promise);
	return promise;
}

async function fetchJson(url: string): Promise<unknown> {
	for (let attempt = 0; attempt < 2; attempt++) {
		const response = await fetch(url, {
			headers: {
				Accept: "application/json",
				"User-Agent": USER_AGENT,
			},
			signal: AbortSignal.timeout(20_000),
		});

		if ((response.status === 429 || response.status >= 500) && attempt === 0) {
			await sleep(retryDelayMs(response));
			continue;
		}

		const text = await response.text();
		let body: unknown;
		try {
			body = JSON.parse(text) as unknown;
		} catch {
			throw new Error(`BAD_RESPONSE ${response.status}`);
		}

		if (!response.ok) {
			throw new Error(problemMessage(body, response.status));
		}
		return body;
	}

	throw new Error("HTTP_RETRY");
}

function retryDelayMs(response: Response): number {
	const retryAfter = Number(response.headers.get("retry-after"));
	const reset = Number(response.headers.get("ratelimit-reset"));
	let seconds = 2;
	if (Number.isFinite(retryAfter) && retryAfter >= 0) {
		seconds = retryAfter;
	} else if (Number.isFinite(reset) && reset >= 0) {
		seconds = reset;
	}
	return Math.min(seconds, 10) * 1000;
}

function problemMessage(body: unknown, status: number): string {
	if (typeof body === "object" && body !== null) {
		const record = body as Record<string, unknown>;
		const code = typeof record.code === "string" ? record.code : `HTTP_${status}`;
		const detail = typeof record.detail === "string" ? record.detail : "";
		return detail ? `${code} ${detail}` : code;
	}
	return `HTTP_${status}`;
}

function readAttribution(body: unknown): string | null {
	if (typeof body !== "object" || body === null) {
		return null;
	}
	const data = (body as Record<string, unknown>).data;
	if (typeof data !== "object" || data === null) {
		return null;
	}
	const attribution = (data as Record<string, unknown>).attribution;
	return typeof attribution === "string" ? attribution : null;
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}
