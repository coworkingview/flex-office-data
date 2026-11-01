import * as fs from 'fs';
import * as path from 'path';

import {
	cityDialogHtml,
	escapeCell,
	formatListings,
	formatMarketRates,
	InputError,
	listingUrl,
	normalizeCity,
	propertiesUrl,
	rateRows,
	ratesUrl,
	resolveBaseUrl,
	snake,
} from '../src/format';

const fixtures = path.resolve(__dirname, '../../../spec/fixtures');

function load(name: string): unknown {
	return JSON.parse(fs.readFileSync(path.join(fixtures, name), 'utf8'));
}

describe('city and API URL', () => {
	test('normalises a display name to a slug', () => {
		expect(normalizeCity(' Berlin ')).toBe('berlin');
		expect(normalizeCity('Abu Dhabi')).toBe('abu-dhabi');
		expect(normalizeCity('new_york')).toBe('new-york');
	});

	test('rejects an empty or punctuated city', () => {
		expect(() => normalizeCity('   ')).toThrow(InputError);
		expect(() => normalizeCity('berlin!')).toThrow(InputError);
	});

	test('keeps the public API when the override is empty', () => {
		expect(resolveBaseUrl('  ')).toBe('https://api.coworkingview.com');
		expect(resolveBaseUrl('https://mirror.example/coworking/')).toBe('https://mirror.example/coworking');
	});

	test('drops a query string and rejects credentials', () => {
		expect(resolveBaseUrl('https://api.coworkingview.com/?utm_source=x')).toBe('https://api.coworkingview.com');
		expect(() => resolveBaseUrl('https://user:secret@api.coworkingview.com')).toThrow(InputError);
		expect(() => resolveBaseUrl('ftp://api.coworkingview.com')).toThrow(InputError);
	});
});

describe('request URLs', () => {
	test('searches one page of properties', () => {
		expect(propertiesUrl('https://api.coworkingview.com/', 'berlin')).toBe(
			'https://api.coworkingview.com/v1/properties?locale=en&city=berlin&page=1&pageSize=20&sortBy=date-desc',
		);
	});

	test('requests market rates with an optional city', () => {
		expect(ratesUrl('https://api.coworkingview.com', 'berlin')).toBe(
			'https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin',
		);
		expect(ratesUrl('https://api.coworkingview.com', null)).toBe(
			'https://api.coworkingview.com/v1/market/rates?locale=en',
		);
	});

	test('builds a listing link without a query string', () => {
		expect(listingUrl('sankt-oberholz-rosenthaler-berlin')).toBe(
			'https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin',
		);
	});
});

describe('workspace search table', () => {
	test('turns the Berlin fixture into listing links and keeps the citation', () => {
		const markdown = formatListings(load('properties_berlin.json'));
		expect(markdown).not.toBeNull();
		const text = markdown as string;
		expect(text).toContain(
			'[St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße](https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin)',
		);
		expect(text).toContain('https://coworkingview.com/en/workspace/smartspaces-berlin-spandau');
		expect(text).toContain('https://coworkingview.com/en/workspace/regus-charlottenburg-berlin');
		expect(text).toContain('| St. Oberholz |');
		expect(text).toContain('Showing 3 of 110 listings.');
		expect(text).toContain('Source: CoworkingView — Coworking spaces in Berlin, https://coworkingview.com/en/coworking/berlin.');
		expect(text).toContain('You may link to listing pages.');
		expect(text).not.toContain('example.com');
		expect(text).not.toContain('Example description');
		expect(text).not.toContain('?');
	});

	test('inserts nothing when the page is empty', () => {
		expect(formatListings(load('properties_empty.json'))).toBeNull();
	});

	test('escapes a pipe in a workspace name', () => {
		const markdown = formatListings({
			data: [{
				slug: 'pipe-space',
				title: 'Room | A',
				city: { slug: 'berlin', name: 'Berlin' },
				operator: { slug: 'op', name: 'Op' },
			}],
			meta: {},
		});
		expect(markdown).toContain('[Room \\| A](https://coworkingview.com/en/workspace/pipe-space)');
		expect(escapeCell('a|b')).toBe('a\\|b');
	});
});

describe('market rates table', () => {
	test('uses figures, then day and hour stats, and skips unpublished cities', () => {
		const markdown = formatMarketRates(load('market_rates.json'));
		expect(markdown).not.toBeNull();
		const text = markdown as string;
		const lines = text.split('\n');
		const berlinFlex = lines.find(line => line.includes('Berlin') && line.includes('Flex desk'));
		expect(berlinFlex).toContain('214');
		expect(berlinFlex).toContain('199');
		expect(berlinFlex).toContain('292');
		expect(berlinFlex).toContain('72');
		expect(lines.filter(line => line.includes('Berlin') && line.includes('Flex desk'))).toHaveLength(1);
		expect(text).toContain('| Berlin | Day pass | day | EUR | 35 |');
		expect(text).toContain('| Berlin | Meeting room | hour | EUR | 32 |');
		expect(text).not.toContain('Example Town');
		expect(text).not.toContain('Regus Al Bateen C6');
		expect(text).toContain('Licensed under CC BY 4.0');
		expect(text).toContain('https://creativecommons.org/licenses/by/4.0/');
		const abuDhabi = lines.find(line => line.includes('Abu Dhabi') && line.includes('Flex desk'));
		expect(abuDhabi).toContain('| yes |');
	});

	test('filters to one city and returns null when that city has no figures', () => {
		const payload = load('market_rates.json');
		const berlin = formatMarketRates(payload, 'berlin') as string;
		expect(berlin).toContain('Berlin');
		expect(berlin).not.toContain('Madrid');
		expect(formatMarketRates(payload, 'example-town')).toBeNull();
		expect(formatMarketRates({ data: { cities: [], unpublished: [{ city: { slug: 'example-town', name: 'Example Town' } }] } })).toBeNull();
	});

	test('falls back to byType when figures is missing and names extra stats', () => {
		expect(snake('eventSpace')).toBe('event_space');
		const rows = rateRows({
			cities: [{
				city: { slug: 'lisbon', name: 'Lisbon' },
				currency: 'EUR',
				byType: [{
					optionType: 'flex_desk',
					median: { amount: 200, currency: 'EUR' },
					sampleSize: 12,
				}],
				eventSpace: {
					median: { amount: 80, currency: 'EUR' },
					sampleSize: 4,
				},
			}],
		});
		expect(rows.map(row => row.product)).toEqual(['flex_desk', 'event_space']);
		expect(rows[0].p25).toBeNull();
		expect(rows[0].unit).toBe('month');
		expect(rows[1].unit).toBe('hour');
		expect(rows[1].lowConfidence).toBe(true);
		const markdown = formatMarketRates({
			data: {
				cities: [{
					city: { slug: 'lisbon', name: 'Lisbon' },
					currency: 'EUR',
					figures: [],
					byType: [{
						optionType: 'private_office',
						median: { amount: 500, currency: 'EUR' },
						sampleSize: 11,
					}],
				}],
				licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
			},
		});
		expect(markdown).toContain('| Lisbon | Private office | month | EUR | 500 |');
		expect(markdown).toContain('License: https://creativecommons.org/licenses/by/4.0/');
	});
});

describe('dialog html', () => {
	test('escapes the prefilled city', () => {
		const html = cityDialogHtml('City', '"><script>');
		expect(html).toContain('value="&quot;&gt;&lt;script&gt;"');
		expect(html).not.toContain('<script>');
	});
});
