import { type FigureId, FIGURES } from "./settings.ts";

export type CityOption = {
	value: string;
	label: string;
};

export type WorkspaceCount = {
	total: number;
	cityName: string;
	citation: string | null;
};

export type MarketRate = {
	citySlug: string;
	cityName: string;
	amount: number;
	currency: string;
	label: string;
	unit: (typeof FIGURES)[FigureId]["unit"];
	sampleSize: number | null;
	attribution: string | null;
	asOf: string | null;
	licenseUrl: string | null;
};

const MONTHLY_FIGURES = new Set<FigureId>(["flex_desk", "fix_desk", "private_office"]);

/**
 * Catalogue size from `GET /v1/properties` (`meta.pagination.total`).
 * The city name comes from the first listing when that listing is in the requested city.
 */
export function parseWorkspaceCount(body: unknown, citySlug: string): WorkspaceCount | null {
	const root = asRecord(body);
	const pagination = asRecord(asRecord(root?.meta)?.pagination);
	const total = pagination?.total;
	if (typeof total !== "number" || !Number.isInteger(total) || total < 0) {
		return null;
	}

	let cityName = citySlug;
	const data = root?.data;
	if (Array.isArray(data) && data.length > 0) {
		const city = asRecord(asRecord(data[0])?.city);
		if (city?.slug === citySlug && typeof city.name === "string" && city.name.length > 0) {
			cityName = city.name;
		}
	}

	const citation = asRecord(asRecord(root?.meta)?.citation);
	return {
		total,
		cityName,
		citation: typeof citation?.text === "string" ? citation.text : null,
	};
}

/**
 * One Price Index median for a city. Returns null when that city or figure is absent.
 * Monthly products are read from `figures[]`; day pass and meeting room are the
 * `dayPass` and `meetingRoom` objects on the city.
 */
export function parseMarketRate(body: unknown, citySlug: string, figure: FigureId): MarketRate | null {
	const data = asRecord(asRecord(body)?.data);
	if (!data || !Array.isArray(data.cities)) {
		return null;
	}

	const city = data.cities.find((item) => asRecord(asRecord(item)?.city)?.slug === citySlug);
	const cityRecord = asRecord(city);
	const cityInfo = asRecord(cityRecord?.city);
	if (!cityRecord || typeof cityInfo?.name !== "string" || cityInfo.name.length === 0) {
		return null;
	}

	const stat = readFigure(cityRecord, figure);
	if (!stat) {
		return null;
	}

	return {
		citySlug,
		cityName: cityInfo.name,
		amount: stat.amount,
		currency: stat.currency,
		label: FIGURES[figure].label,
		unit: FIGURES[figure].unit,
		sampleSize: stat.sampleSize,
		attribution: typeof data.attribution === "string" ? data.attribution : null,
		asOf: typeof data.asOf === "string" ? data.asOf : null,
		licenseUrl: typeof data.licenseUrl === "string" ? data.licenseUrl : null,
	};
}

/** Published cities from `GET /v1/market/rates`, sorted by display name. */
export function parseCityOptions(body: unknown): CityOption[] {
	const cities = asRecord(asRecord(body)?.data)?.cities;
	if (!Array.isArray(cities)) {
		return [];
	}

	const options: CityOption[] = [];
	for (const item of cities) {
		const city = asRecord(asRecord(item)?.city);
		if (typeof city?.slug !== "string" || typeof city.name !== "string") {
			continue;
		}
		if (!/^[a-z0-9][a-z0-9._-]*$/.test(city.slug) || city.name.length === 0) {
			continue;
		}
		options.push({ value: city.slug, label: city.name });
	}

	options.sort((a, b) => a.label.localeCompare(b.label, "en"));
	return options;
}

function readFigure(
	city: Record<string, unknown>,
	figure: FigureId,
): { amount: number; currency: string; sampleSize: number | null } | null {
	if (MONTHLY_FIGURES.has(figure)) {
		if (!Array.isArray(city.figures)) {
			return null;
		}
		const match = city.figures.find((item) => asRecord(item)?.optionType === figure);
		return readMoney(match);
	}

	const key = figure === "day_pass" ? "dayPass" : "meetingRoom";
	return readMoney(city[key]);
}

function readMoney(stat: unknown): { amount: number; currency: string; sampleSize: number | null } | null {
	const record = asRecord(stat);
	const median = asRecord(record?.median);
	const amount = median?.amount;
	const currency = median?.currency;
	if (typeof amount !== "number" || !Number.isFinite(amount)) {
		return null;
	}
	if (typeof currency !== "string" || currency.length === 0) {
		return null;
	}
	const sampleSize = record?.sampleSize;
	return {
		amount,
		currency,
		sampleSize: typeof sampleSize === "number" && Number.isFinite(sampleSize) ? sampleSize : null,
	};
}

function asRecord(value: unknown): Record<string, unknown> | null {
	if (typeof value === "object" && value !== null && !Array.isArray(value)) {
		return value as Record<string, unknown>;
	}
	return null;
}
