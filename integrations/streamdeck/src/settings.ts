/**
 * Public site opened when a key is pressed. No www: that host is the canonical site.
 */
export const SITE_URL = "https://coworkingview.com";

/** How often visible keys re-read the public API. */
export const REFRESH_INTERVAL_MS = 30 * 60 * 1000;

/** City used when a key has no setting yet. */
export const DEFAULT_CITY = "berlin";

/**
 * Price Index figures this plugin can show. Each one is a field on the
 * city object returned by `GET /v1/market/rates`.
 */
export const FIGURES = {
	flex_desk: { label: "Flex desk", unit: "month" },
	fix_desk: { label: "Fixed desk", unit: "month" },
	private_office: { label: "Private office", unit: "month" },
	day_pass: { label: "Day pass", unit: "day" },
	meeting_room: { label: "Meeting room", unit: "hour" },
} as const;

export type FigureId = keyof typeof FIGURES;

export type ActionSettings = {
	city?: string;
	figure?: string;
};

const SLUG = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/**
 * City slug from the property inspector, or {@link DEFAULT_CITY}.
 */
export function cityOf(settings: ActionSettings): string {
	const city = settings.city?.trim().toLowerCase();
	if (city && SLUG.test(city)) {
		return city;
	}
	return DEFAULT_CITY;
}

/**
 * Which Price Index figure to show. Unknown values fall back to the flex desk median.
 */
export function figureOf(settings: ActionSettings): FigureId {
	const figure = settings.figure;
	if (figure && figure in FIGURES) {
		return figure as FigureId;
	}
	return "flex_desk";
}

/** Render an amount the way the API sent it, without added rounding. */
export function formatAmount(amount: number): string {
	if (!Number.isFinite(amount)) {
		return "—";
	}
	return Number.isInteger(amount) ? String(amount) : String(amount);
}

export function workspaceTitle(total: number, cityName: string): string {
	return `${total}\n${cityName}`;
}

export function rateTitle(amount: number, currency: string, label: string, cityName: string): string {
	return `${formatAmount(amount)} ${currency}\n${label}\n${cityName}`;
}
