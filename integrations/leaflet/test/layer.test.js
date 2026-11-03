import { afterEach, describe, expect, it, vi } from 'vitest';
import L from 'leaflet';
import fixture from '../../../spec/fixtures/market_rates.json' with { type: 'json' };
import coordinates from '../src/city-coordinates.json' with { type: 'json' };
import { ATTRIBUTION, layer } from '../src/index.js';

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function mountMap() {
  const element = document.createElement('div');
  element.style.width = '400px';
  element.style.height = '300px';
  document.body.appendChild(element);
  const map = L.map(element, { center: [48, 8], zoom: 4 });
  return { element, map };
}

function markerBySlug(group, slug) {
  return group.getLayers().find((item) => item.options.citySlug === slug);
}

describe('city coordinates', () => {
  it('keeps GeoNames centroids for published fixture cities and omits ambiguous names', () => {
    expect(coordinates.source.name).toBe('GeoNames');
    expect(coordinates.source.license).toBe('CC BY 4.0');
    expect(coordinates.cities.berlin).toMatchObject({
      geonameId: 2950159,
      name: 'Berlin',
      countryCode: 'DE',
      lat: 52.52437,
      lng: 13.41053,
    });
    expect(coordinates.cities.madrid.geonameId).toBe(3117735);
    expect(coordinates.cities['abu-dhabi'].geonameId).toBe(292968);
    expect(coordinates.cities.frankfurt).toMatchObject({
      geonameId: 2925533,
      name: 'Frankfurt am Main',
    });
    expect(coordinates.cities['frankfurt-oder'].geonameId).toBe(2925535);
    for (const slug of ['ashford', 'casalecchio', 'coleshill', 'example-town']) {
      expect(coordinates.cities[slug]).toBeUndefined();
    }
    expect(coordinates.omitted.map((row) => row.slug).sort()).toEqual(['ashford', 'casalecchio', 'coleshill']);
    for (const row of Object.values(coordinates.cities)) {
      expect(row.lat).toBeGreaterThanOrEqual(-90);
      expect(row.lat).toBeLessThanOrEqual(90);
      expect(row.lng).toBeGreaterThanOrEqual(-180);
      expect(row.lng).toBeLessThanOrEqual(180);
    }
  });
});

describe('L.coworkingView layer', () => {
  let map;
  let element;

  afterEach(() => {
    if (map) map.remove();
    element?.remove();
    map = undefined;
    element = undefined;
    vi.restoreAllMocks();
  });

  it('does not fetch when the module is evaluated', async () => {
    const fetchMock = vi.fn(() => { throw new Error('fetch during import'); });
    vi.stubGlobal('fetch', fetchMock);
    vi.resetModules();
    await import('../src/index.js');
    expect(fetchMock).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  it('adds a marker and popup per published city and credits CoworkingView', async () => {
    ({ map, element } = mountMap());
    const fetchMock = vi.fn(async () => jsonResponse(fixture));
    const priceLayer = layer({ fetch: fetchMock, sleep: async () => {} });
    const loaded = new Promise((resolve, reject) => {
      priceLayer.once('load', resolve);
      priceLayer.once('error', (event) => reject(event.error));
    });
    priceLayer.addTo(map);
    const summary = await loaded;

    const published = fixture.data.cities.map((city) => city.city.slug);
    expect(priceLayer.getLayers().map((item) => item.options.citySlug).sort()).toEqual([...published].sort());
    expect(summary.unlocated).toEqual([]);
    expect(summary.attribution).toBe(fixture.data.attribution);
    expect(summary.license).toBe(fixture.data.license);
    expect(summary.licenseUrl).toBe(fixture.data.licenseUrl);

    const berlin = fixture.data.cities.find((city) => city.city.slug === 'berlin');
    const popup = markerBySlug(priceLayer, 'berlin').getPopup().getContent();
    expect(popup).toContain(berlin.city.name);
    expect(popup).toContain(`Median ${berlin.entryMedian.amount} ${berlin.entryMedian.currency}`);
    expect(popup).toContain(fixture.data.attribution);
    const flex = berlin.figures.find((row) => row.optionType === 'flex_desk');
    expect(popup).toContain(`flex_desk: ${flex.median.amount} ${flex.median.currency}`);
    expect(popup).not.toContain('example-town');

    const credits = Object.keys(map.attributionControl._attributions).join('\n');
    expect(credits).toBe(ATTRIBUTION);
    expect(credits).toContain('href="https://coworkingview.com"');
    expect(credits).toContain('CoworkingView');
    expect(credits).toContain('CC BY 4.0');
    expect(credits).toContain('https://creativecommons.org/licenses/by/4.0/');
    expect(credits).toContain('https://www.geonames.org/');
    expect(markerBySlug(priceLayer, 'berlin').options.alt).toContain(String(berlin.entryMedian.amount));
    expect(markerBySlug(priceLayer, 'berlin').options.keyboard).toBe(true);
  });

  it('uses caller coordinates and skips cities that still have none', async () => {
    ({ map, element } = mountMap());
    const body = {
      data: {
        cities: [
          {
            city: { slug: 'made-up', name: '<b>Made Up</b>' },
            currency: 'EUR',
            entryMedian: { amount: 10, currency: 'EUR' },
          },
          {
            city: { slug: 'ashford', name: 'Ashford' },
            currency: 'GBP',
            entryMedian: { amount: 20, currency: 'GBP' },
          },
        ],
        unpublished: [{ city: { slug: 'example-town', name: 'Example Town' } }],
        attribution: 'credit',
      },
    };
    const fetchMock = vi.fn(async () => jsonResponse(body));
    const priceLayer = layer({
      fetch: fetchMock,
      sleep: async () => {},
      coordinates: { 'made-up': [41.5, 2.2] },
    });
    const summary = await new Promise((resolve, reject) => {
      priceLayer.once('load', resolve);
      priceLayer.once('error', (event) => reject(event.error));
      priceLayer.addTo(map);
    });
    expect(summary.unlocated).toEqual(['ashford']);
    expect(priceLayer.getLayers()).toHaveLength(1);
    const marker = markerBySlug(priceLayer, 'made-up');
    expect(marker.getLatLng()).toMatchObject({ lat: 41.5, lng: 2.2 });
    expect(marker.getPopup().getContent()).toContain('&lt;b&gt;Made Up&lt;/b&gt;');
    expect(marker.getPopup().getContent()).toContain('Median 10 EUR');
    expect(marker.getPopup().getContent()).not.toContain('<b>Made Up</b>');
  });

  it('fires error and leaves the map unmarked when the API rejects the query', async () => {
    ({ map, element } = mountMap());
    const fetchMock = vi.fn(async () => jsonResponse({
      title: 'Bad currency',
      status: 400,
      code: 'VALIDATION',
      detail: 'currency is not supported',
    }, 400));
    const priceLayer = layer({ fetch: fetchMock, sleep: async () => {} });
    const error = await new Promise((resolve) => {
      priceLayer.once('error', (event) => resolve(event.error));
      priceLayer.addTo(map);
    });
    expect(error.code).toBe('VALIDATION');
    expect(priceLayer.getLayers()).toHaveLength(0);
    expect(Object.keys(map.attributionControl._attributions).join('\n')).toContain('https://coworkingview.com');
  });
});
