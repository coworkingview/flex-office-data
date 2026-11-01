/**
 * Pure formatting for the two public responses this plugin inserts into a note.
 *
 * `GET /v1/properties` becomes a table of listing links (SPEC section 5).
 * `GET /v1/market/rates` becomes a table of city × product prices (SPEC section 3).
 * Photos, logos and descriptions are not copied into the note.
 */

export const DEFAULT_BASE_URL = 'https://api.coworkingview.com';
export const SITE_URL = 'https://coworkingview.com';
export const LOCALE = 'en';
export const WORKSPACE_PATH = 'workspace';
export const SEARCH_PAGE_SIZE = 20;

const PRODUCT_ORDER = [
	'flex_desk',
	'fix_desk',
	'private_office',
	'exclusive_bereich',
	'day_pass',
	'meeting_room',
	'event_space',
	'virtual_office',
	'membership',
];

const PRODUCT_LABELS: Record<string, string> = {
	flex_desk: 'Flex desk',
	fix_desk: 'Dedicated desk',
	private_office: 'Private office',
	exclusive_bereich: 'Exclusive area',
	day_pass: 'Day pass',
	meeting_room: 'Meeting room',
	event_space: 'Event space',
	virtual_office: 'Virtual office',
	membership: 'Membership',
};

const STAT_UNITS: Record<string, string> = {
	day_pass: 'day',
	meeting_room: 'hour',
	event_space: 'hour',
	virtual_office: 'month',
};

const SLUG_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const CITY_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const LOW_CONFIDENCE_BELOW = 10;

export class InputError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'InputError';
	}
}

export class FormatError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'FormatError';
	}
}

export interface ListingRow {
	title: string;
	city: string;
	operator: string;
	url: string;
}

export interface RateRow {
	citySlug: string;
	cityName: string;
	currency: string;
	product: string;
	unit: string | null;
	median: number;
	p25: number | null;
	p75: number | null;
	sampleSize: number;
	lowConfidence: boolean;
}

export function normalizeCity(value: string): string {
	const slug = value.trim().toLowerCase().replace(/[\s_]+/g, '-');
	if (!CITY_PATTERN.test(slug)) {
		throw new InputError('Enter a city slug such as berlin or abu-dhabi.');
	}
	return slug;
}

/** API root. An empty override keeps the public API. Search and hash are dropped. */
export function resolveBaseUrl(override: string): string {
	const trimmed = override.trim();
	if (!trimmed) return DEFAULT_BASE_URL;
	let url: URL;
	try {
		url = new URL(trimmed);
	} catch {
		throw new InputError('API URL must be an http or https address, for example https://api.coworkingview.com.');
	}
	if (url.username || url.password) {
		throw new InputError('API URL must not include a username or password.');
	}
	if (url.protocol !== 'https:' && url.protocol !== 'http:') {
		throw new InputError('API URL must start with https:// or http://.');
	}
	const path = url.pathname.replace(/\/+$/, '');
	return `${url.origin}${path}`;
}

export function propertiesUrl(baseUrl: string, city: string): string {
	const params = new URLSearchParams({
		locale: LOCALE,
		city,
		page: '1',
		pageSize: String(SEARCH_PAGE_SIZE),
		sortBy: 'date-desc',
	});
	return `${trimSlash(baseUrl)}/v1/properties?${params.toString()}`;
}

export function ratesUrl(baseUrl: string, city: string | null): string {
	const params = new URLSearchParams({ locale: LOCALE });
	if (city) params.set('city', city);
	return `${trimSlash(baseUrl)}/v1/market/rates?${params.toString()}`;
}

export function listingUrl(slug: string): string {
	return `${SITE_URL}/${LOCALE}/${WORKSPACE_PATH}/${slug}`;
}

export function escapeHtml(value: string): string {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

export function cityDialogHtml(message: string, value: string): string {
	return [
		'<form name="coworkingview">',
		`<p>${escapeHtml(message)}</p>`,
		'<label for="cwv-city">City</label><br>',
		`<input id="cwv-city" type="text" name="city" value="${escapeHtml(value)}">`,
		'</form>',
	].join('');
}

export function snake(key: string): string {
	return key.replace(/[A-Z]/g, (letter, index: number) => (index === 0 ? letter : `_${letter}`)).toLowerCase();
}

/**
 * Markdown for one page of listings, or null when the page has no rows.
 * The citation and catalogue notice travel with the table.
 */
export function formatListings(payload: unknown): string | null {
	const data = envelopeData(payload, 'listings');
	if (!Array.isArray(data)) {
		throw new FormatError('The CoworkingView API returned listings in an unexpected shape.');
	}
	const rows = listingRows(data);
	if (!rows.length) return null;
	const meta = envelopeMeta(payload);
	const lines = [
		markdownTable(
			['Workspace', 'City', 'Operator', 'Listing'],
			rows.map(row => [markdownLink(row.title, row.url), row.city, row.operator, row.url]),
		),
	];
	const total = metaPaginationTotal(meta);
	if (typeof total === 'number') {
		lines.push('', `Showing ${rows.length} of ${total} listings.`);
	}
	const citation = citationText(meta);
	if (citation) lines.push('', citation);
	const notice = typeof meta.catalogueNotice === 'string' ? meta.catalogueNotice : '';
	if (notice) lines.push('', notice);
	return lines.join('\n');
}

/**
 * Markdown for the Price Index, or null when the response has no published figures.
 * Pass a city slug to keep only that city. Attribution is kept with the table.
 */
export function formatMarketRates(payload: unknown, city: string | null = null): string | null {
	const data = envelopeData(payload, 'market rates');
	if (!data || typeof data !== 'object' || Array.isArray(data)) {
		throw new FormatError('The CoworkingView API returned market rates in an unexpected shape.');
	}
	let rows = rateRows(data as Record<string, unknown>);
	if (city) rows = rows.filter(row => row.citySlug === city);
	if (!rows.length) return null;
	const record = data as Record<string, unknown>;
	const lines = [
		markdownTable(
			['City', 'Product', 'Unit', 'Currency', 'Median', 'P25', 'P75', 'Sample size', 'Low confidence'],
			rows.map(row => [
				row.cityName,
				productLabel(row.product),
				row.unit ?? '',
				row.currency,
				formatNumber(row.median),
				formatNumber(row.p25),
				formatNumber(row.p75),
				formatNumber(row.sampleSize),
				row.lowConfidence ? 'yes' : '',
			]),
		),
	];
	const attribution = typeof record.attribution === 'string' ? record.attribution : '';
	if (attribution) {
		lines.push('', attribution);
	} else if (typeof record.licenseUrl === 'string' && record.licenseUrl) {
		lines.push('', `License: ${record.licenseUrl}`);
	}
	return lines.join('\n');
}

export function listingRows(cards: unknown[]): ListingRow[] {
	const rows: ListingRow[] = [];
	for (const card of cards) {
		if (!card || typeof card !== 'object' || Array.isArray(card)) continue;
		const record = card as Record<string, unknown>;
		const slug = typeof record.slug === 'string' ? record.slug : '';
		const title = typeof record.title === 'string' ? record.title.trim() : '';
		if (!title || !SLUG_PATTERN.test(slug)) continue;
		const city = record.city;
		const operator = record.operator;
		rows.push({
			title,
			city: nestedName(city) || nestedString(city, 'slug'),
			operator: nestedName(operator),
			url: listingUrl(slug),
		});
	}
	return rows;
}

export function rateRows(data: Record<string, unknown>): RateRow[] {
	const cities = Array.isArray(data.cities) ? data.cities : [];
	const rows: RateRow[] = [];
	for (const city of cities) {
		if (!city || typeof city !== 'object' || Array.isArray(city)) continue;
		const record = city as Record<string, unknown>;
		const cityObj = record.city;
		const citySlug = nestedString(cityObj, 'slug');
		const cityName = nestedName(cityObj) || citySlug;
		const currency = typeof record.currency === 'string' ? record.currency : '';
		if (!citySlug) continue;
		const figures = Array.isArray(record.figures) && record.figures.length
			? record.figures
			: (Array.isArray(record.byType) ? record.byType : []);
		for (const item of figures) {
			const row = figureRow(item, citySlug, cityName, currency, 'month');
			if (row) rows.push(row);
		}
		for (const key of Object.keys(record)) {
			const value = record[key];
			if (!isStat(value)) continue;
			const product = snake(key);
			const row = figureRow(
				{
					optionType: product,
					median: value.median,
					p25: value.p25,
					p75: value.p75,
					sampleSize: value.sampleSize,
				},
				citySlug,
				cityName,
				currency,
				Object.prototype.hasOwnProperty.call(STAT_UNITS, product) ? STAT_UNITS[product] : null,
			);
			if (row) rows.push(row);
		}
	}
	rows.sort((a, b) => {
		if (a.citySlug < b.citySlug) return -1;
		if (a.citySlug > b.citySlug) return 1;
		return productRank(a.product) - productRank(b.product) || a.product.localeCompare(b.product);
	});
	return rows;
}

function figureRow(
	item: unknown,
	citySlug: string,
	cityName: string,
	currency: string,
	unit: string | null,
): RateRow | null {
	if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
	const record = item as Record<string, unknown>;
	const product = typeof record.optionType === 'string' ? record.optionType : '';
	const median = amount(record.median);
	const sampleSize = finiteNumber(record.sampleSize);
	if (!product || median === null || sampleSize === null) return null;
	return {
		citySlug,
		cityName,
		currency,
		product,
		unit,
		median,
		p25: amount(record.p25),
		p75: amount(record.p75),
		sampleSize,
		lowConfidence: sampleSize < LOW_CONFIDENCE_BELOW,
	};
}

function productRank(product: string): number {
	const index = PRODUCT_ORDER.indexOf(product);
	return index === -1 ? PRODUCT_ORDER.length : index;
}

function productLabel(product: string): string {
	return PRODUCT_LABELS[product] || product.replace(/_/g, ' ');
}

function isStat(value: unknown): value is { median: unknown; sampleSize: unknown; p25?: unknown; p75?: unknown } {
	return !!value && typeof value === 'object' && !Array.isArray(value)
		&& Object.prototype.hasOwnProperty.call(value, 'median')
		&& Object.prototype.hasOwnProperty.call(value, 'sampleSize');
}

function amount(money: unknown): number | null {
	if (!money || typeof money !== 'object' || Array.isArray(money)) return null;
	return finiteNumber((money as Record<string, unknown>).amount);
}

function finiteNumber(value: unknown): number | null {
	return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function formatNumber(value: number | null): string {
	if (value === null) return '';
	return String(value);
}

function nestedName(value: unknown): string {
	return nestedString(value, 'name');
}

function nestedString(value: unknown, key: string): string {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
	const nested = (value as Record<string, unknown>)[key];
	return typeof nested === 'string' ? nested : '';
}

function envelopeData(payload: unknown, label: string): unknown {
	if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
		throw new FormatError(`The CoworkingView API returned ${label} that are not a JSON object.`);
	}
	if (!Object.prototype.hasOwnProperty.call(payload, 'data')) {
		throw new FormatError(`The CoworkingView API response has no '${label}' data.`);
	}
	return (payload as Record<string, unknown>).data;
}

function envelopeMeta(payload: unknown): Record<string, unknown> {
	if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return {};
	const meta = (payload as Record<string, unknown>).meta;
	if (!meta || typeof meta !== 'object' || Array.isArray(meta)) return {};
	return meta as Record<string, unknown>;
}

function metaPaginationTotal(meta: Record<string, unknown>): number | null {
	const pagination = meta.pagination;
	if (!pagination || typeof pagination !== 'object' || Array.isArray(pagination)) return null;
	return finiteNumber((pagination as Record<string, unknown>).total);
}

function citationText(meta: Record<string, unknown>): string {
	const citation = meta.citation;
	if (!citation || typeof citation !== 'object' || Array.isArray(citation)) return '';
	const text = (citation as Record<string, unknown>).text;
	return typeof text === 'string' ? text : '';
}

export function escapeCell(value: string): string {
	return value.replace(/\|/g, '\\|').replace(/\r?\n/g, ' ').trim();
}

export function markdownTable(headers: string[], rows: string[][]): string {
	const header = `| ${headers.map(escapeCell).join(' | ')} |`;
	const rule = `| ${headers.map(() => '---').join(' | ')} |`;
	const body = rows.map(row => `| ${row.map(escapeCell).join(' | ')} |`);
	return [header, rule, ...body].join('\n');
}

function markdownLink(title: string, url: string): string {
	const text = title.replace(/\\/g, '\\\\').replace(/\[/g, '\\[').replace(/\]/g, '\\]');
	return `[${text}](${url})`;
}

function trimSlash(baseUrl: string): string {
	return baseUrl.replace(/\/+$/, '');
}
