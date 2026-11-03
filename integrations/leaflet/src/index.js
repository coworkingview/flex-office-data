import { LayerGroup, Marker } from 'leaflet';
import coordinates from './city-coordinates.json' with { type: 'json' };
import { fetchRates, CoworkingViewError } from './rates.js';

export { fetchRates, CoworkingViewError } from './rates.js';
export { VERSION, USER_AGENT, DEFAULT_URL } from './rates.js';

const CITY_TABLE = coordinates.cities ?? {};

export const ATTRIBUTION =
  '<a href="https://coworkingview.com">CoworkingView</a> Price Index ' +
  '(<a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>)' +
  ' | City locations © <a href="https://www.geonames.org/">GeoNames</a> ' +
  '(<a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>)';

export const CoworkingViewLayer = LayerGroup.extend({
  options: {
    attribution: ATTRIBUTION,
    url: 'https://api.coworkingview.com/v1/market/rates',
    locale: 'en',
    fitBounds: false,
  },

  initialize(options) {
    LayerGroup.prototype.initialize.call(this, undefined, options);
    if (!this.options.attribution) this.options.attribution = ATTRIBUTION;
    this._loaded = false;
    this._loading = false;
    this._token = 0;
    this._summary = null;
  },

  onAdd(map) {
    LayerGroup.prototype.onAdd.call(this, map);
    if (!this._loaded && !this._loading) {
      // The error event reports failure. Swallow the rejection here so a
      // layer added with addTo does not become an unhandled promise rejection.
      this._load().catch(() => {});
    }
    return this;
  },

  reload() {
    return this._load();
  },

  _load() {
    const token = ++this._token;
    this._loading = true;
    this._loaded = false;
    this.fire('loading');
    return fetchRates({
      url: this.options.url,
      locale: this.options.locale,
      city: this.options.city,
      country: this.options.country,
      currency: this.options.currency,
      fetch: this.options.fetch,
      sleep: this.options.sleep,
      timeoutMs: this.options.timeoutMs,
      userAgent: this.options.userAgent,
    }).then(
      (payload) => {
        if (token !== this._token) return undefined;
        const summary = this._render(payload);
        this._loaded = true;
        this._loading = false;
        this.fire('load', summary);
        return summary;
      },
      (error) => {
        if (token !== this._token) return undefined;
        this._loading = false;
        const wrapped = error instanceof CoworkingViewError
          ? error
          : new CoworkingViewError(error && error.message ? error.message : 'request failed', {
            code: 'CONNECTION',
            status: 0,
          });
        this.fire('error', { error: wrapped });
        return Promise.reject(wrapped);
      },
    );
  },

  _render(payload) {
    this.clearLayers();
    const data = payload.data;
    const cities = Array.isArray(data.cities) ? data.cities : [];
    const unlocated = [];
    for (const city of cities) {
      if (!city || typeof city !== 'object') continue;
      const ref = city.city && typeof city.city === 'object' ? city.city : {};
      const slug = typeof ref.slug === 'string' ? ref.slug.trim() : '';
      if (!slug) continue;
      const point = locate(slug, this.options.coordinates);
      if (!point) {
        unlocated.push(slug);
        continue;
      }
      const median = cityMedian(city);
      const title = markerTitle(typeof ref.name === 'string' ? ref.name : slug, median);
      const marker = new Marker(point, {
        title,
        alt: title,
        keyboard: true,
        citySlug: slug,
      });
      marker.bindPopup(popupHtml(city, median, data));
      this.addLayer(marker);
    }
    const summary = {
      cities: this.getLayers().length,
      unlocated,
      attribution: typeof data.attribution === 'string' ? data.attribution : null,
      license: typeof data.license === 'string' ? data.license : null,
      licenseUrl: typeof data.licenseUrl === 'string' ? data.licenseUrl : null,
      asOf: typeof data.asOf === 'string' ? data.asOf : null,
    };
    this._summary = summary;
    if (this.options.fitBounds && this._map && this.getLayers().length) {
      const bounds = this.getBounds();
      if (bounds.isValid()) this._map.fitBounds(bounds, { padding: [24, 24] });
    }
    return summary;
  },
});

export function layer(options) {
  return new CoworkingViewLayer(options);
}

export const coworkingView = { layer };

function locate(slug, userCoordinates) {
  const table = CITY_TABLE[slug];
  const user = userCoordinates && Object.prototype.hasOwnProperty.call(userCoordinates, slug)
    ? userCoordinates[slug]
    : undefined;
  return parseLatLng(user) || (table ? parseLatLng(table) : null);
}

function parseLatLng(value) {
  if (!value) return null;
  const lat = Array.isArray(value) ? value[0] : value.lat;
  const lng = Array.isArray(value) ? value[1] : value.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { lat, lng };
}

function money(value) {
  if (!value || typeof value !== 'object') return null;
  if (typeof value.amount !== 'number' || !Number.isFinite(value.amount)) return null;
  return {
    amount: value.amount,
    currency: typeof value.currency === 'string' ? value.currency : '',
  };
}

function figureRows(city) {
  const source = Array.isArray(city.figures) && city.figures.length ? city.figures : city.byType;
  if (!Array.isArray(source)) return [];
  return source.filter((row) => row && typeof row === 'object').map((row) => ({
    optionType: typeof row.optionType === 'string' ? row.optionType : '',
    median: money(row.median),
  }));
}

function cityMedian(city) {
  const entry = money(city.entryMedian);
  if (entry) return { ...entry, label: 'Median' };
  const figures = figureRows(city);
  const chosen = figures.find((row) => row.optionType === 'flex_desk' && row.median)
    || figures.find((row) => row.median);
  if (!chosen || !chosen.median) return null;
  const label = chosen.optionType ? `Median (${chosen.optionType})` : 'Median';
  return { ...chosen.median, label };
}

function markerTitle(name, median) {
  if (!median) return name;
  return `${name}: ${median.amount} ${median.currency}`.trim();
}

function popupHtml(city, median, data) {
  const ref = city.city && typeof city.city === 'object' ? city.city : {};
  const name = typeof ref.name === 'string' ? ref.name : '';
  const parts = [`<strong>${escapeHtml(name)}</strong>`];
  if (median) {
    parts.push(
      `<div>${escapeHtml(median.label)} ${escapeHtml(String(median.amount))} ${escapeHtml(median.currency)}</div>`,
    );
  }
  const figures = figureRows(city).filter((row) => row.median && row.optionType);
  if (figures.length) {
    const items = figures.map((row) => (
      `<li>${escapeHtml(row.optionType)}: ${escapeHtml(String(row.median.amount))} ${escapeHtml(row.median.currency)}</li>`
    )).join('');
    parts.push(`<ul>${items}</ul>`);
  }
  if (typeof city.sampleSize === 'number') {
    parts.push(`<div>Sample size ${escapeHtml(String(city.sampleSize))}</div>`);
  }
  if (typeof data.asOf === 'string' && data.asOf) {
    parts.push(`<div>As of ${escapeHtml(data.asOf)}</div>`);
  }
  if (typeof data.attribution === 'string' && data.attribution) {
    parts.push(`<div class="leaflet-coworkingview-attribution">${escapeHtml(data.attribution)}</div>`);
  }
  return `<div class="leaflet-coworkingview-popup">${parts.join('')}</div>`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[ch]));
}
