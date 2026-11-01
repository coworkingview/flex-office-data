/**
 * Reads CoworkingView public API payloads. No network.
 *
 * GET /v1/market/rates — Price Index. The CC BY 4.0 text is data.attribution
 * and is returned unchanged. GET /v1/properties — the catalogue size is
 * meta.pagination.total, which is not the price-index propertyCount and not
 * the length of data.
 *
 * Field names are the ones the Swift and OCaml clients read (clients/swift,
 * clients/ocaml) and that spec/SPEC.md documents. A missing number stays
 * null. It is never turned into zero. Listing titles, photos and logos are
 * not copied onto the result.
 */

export const API_ORIGIN = "https://api.coworkingview.com";
export const DEFAULT_CITY = "berlin";
export const CITY_STORAGE_KEY = "city";

const SLUG = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

const PRODUCT_ORDER = [
  "flex_desk",
  "fix_desk",
  "private_office",
  "exclusive_bereich",
  "day_pass",
  "meeting_room",
  "event_space",
  "virtual_office",
  "membership",
];

/** Units for top-level aggregates. Anything else has no unit. */
const STAT_UNITS = {
  day_pass: "day",
  meeting_room: "hour",
  event_space: "hour",
  virtual_office: "month",
};

export function isSlug(value) {
  return typeof value === "string" && SLUG.test(value);
}

/** Thunderbird UI language to the locale the API accepts (en, de, es). */
export function uiLocale(language) {
  if (typeof language !== "string" || language.length === 0) {
    return "en";
  }
  const base = language.toLowerCase().split("-")[0];
  if (base === "en" || base === "de" || base === "es") {
    return base;
  }
  return "en";
}

/**
 * Published cities from GET /v1/market/rates (data.cities only).
 * data.unpublished is ignored: those cities have no figures.
 */
export function parseCities(body) {
  const cities = asRecord(asRecord(body)?.data)?.cities;
  if (!Array.isArray(cities)) {
    return [];
  }
  const options = [];
  for (const item of cities) {
    const city = asRecord(asRecord(item)?.city);
    if (!city || !isSlug(city.slug) || typeof city.name !== "string" || city.name.length === 0) {
      continue;
    }
    options.push({ slug: city.slug, name: city.name });
  }
  options.sort(
    (a, b) => a.name.localeCompare(b.name, "en") || a.slug.localeCompare(b.slug, "en"),
  );
  return options;
}

/**
 * One city's Price Index rows.
 * Monthly products come from figures[] when that array is present and
 * non-empty, otherwise from byType[] (p25 and p75 are then null, because
 * byType does not carry them). Objects on the city that have median and
 * sampleSize (dayPass, meetingRoom, and any later aggregate of that shape)
 * are added as well. Returns null when the slug is not in data.cities.
 */
export function parseCityRates(body, slug) {
  const data = asRecord(asRecord(body)?.data);
  if (!data || !Array.isArray(data.cities)) {
    return null;
  }
  const match = data.cities.find((item) => asRecord(asRecord(item)?.city)?.slug === slug);
  const city = asRecord(match);
  const info = asRecord(city?.city);
  if (!city || typeof info?.name !== "string" || !isSlug(info.slug)) {
    return null;
  }

  const products = [];
  const figures = Array.isArray(city.figures) && city.figures.length > 0 ? city.figures : null;
  const series = figures ?? (Array.isArray(city.byType) ? city.byType : []);
  for (const item of series) {
    const row = monthlyProduct(item, figures === null);
    if (row) {
      products.push(row);
    }
  }
  for (const [key, value] of Object.entries(city)) {
    if (!isStat(value)) {
      continue;
    }
    const product = camelToSnake(key);
    const row = statProduct(product, value, STAT_UNITS[product] ?? null);
    if (row) {
      products.push(row);
    }
  }
  products.sort(compareProducts);

  return {
    citySlug: info.slug,
    cityName: info.name,
    countryCode: typeof city.countryCode === "string" ? city.countryCode : null,
    currency: typeof city.currency === "string" ? city.currency : null,
    products,
    attribution: typeof data.attribution === "string" ? data.attribution : null,
    license: typeof data.license === "string" ? data.license : null,
    licenseUrl: httpsUrl(data.licenseUrl),
    asOf: typeof data.asOf === "string" ? data.asOf : null,
  };
}

/**
 * Catalogue size from GET /v1/properties. Returns null when
 * meta.pagination.total is missing, so the caller can say the count failed
 * instead of showing zero. The listing array is not read.
 */
export function parseWorkspaceCount(body) {
  const meta = asRecord(asRecord(body)?.meta);
  const pagination = asRecord(meta?.pagination);
  const total = pagination?.total;
  if (typeof total !== "number" || !Number.isInteger(total) || total < 0) {
    return null;
  }
  const citation = asRecord(meta?.citation);
  return {
    total,
    citation: typeof citation?.text === "string" ? citation.text : null,
    citationUrl: httpsUrl(citation?.url),
  };
}

export function httpsUrl(value) {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") {
    return null;
  }
  return url.toString();
}

function monthlyProduct(item, fromByType) {
  const record = asRecord(item);
  if (!record || typeof record.optionType !== "string" || record.optionType.length === 0) {
    return null;
  }
  const median = money(record.median);
  if (!median) {
    return null;
  }
  const sampleSize = integer(record.sampleSize);
  return {
    product: record.optionType,
    unit: "month",
    median,
    p25: fromByType ? null : money(record.p25),
    p75: fromByType ? null : money(record.p75),
    sampleSize,
    lowConfidence: sampleSize !== null && sampleSize < 10,
  };
}

function statProduct(product, value, unit) {
  const median = money(value.median);
  if (!median) {
    return null;
  }
  const sampleSize = integer(value.sampleSize);
  return {
    product,
    unit,
    median,
    p25: money(value.p25),
    p75: money(value.p75),
    sampleSize,
    lowConfidence: sampleSize !== null && sampleSize < 10,
  };
}

function compareProducts(a, b) {
  const rank = rankOf(a.product) - rankOf(b.product);
  if (rank !== 0) {
    return rank;
  }
  if (a.product < b.product) {
    return -1;
  }
  if (a.product > b.product) {
    return 1;
  }
  return 0;
}

function rankOf(product) {
  const index = PRODUCT_ORDER.indexOf(product);
  return index === -1 ? PRODUCT_ORDER.length : index;
}

function isStat(value) {
  const record = asRecord(value);
  if (!record || !asRecord(record.median)) {
    return false;
  }
  return typeof record.sampleSize === "number";
}

function camelToSnake(key) {
  return key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

function money(node) {
  const record = asRecord(node);
  if (!record || typeof record.amount !== "number" || !Number.isFinite(record.amount)) {
    return null;
  }
  return {
    amount: record.amount,
    currency: typeof record.currency === "string" ? record.currency : null,
  };
}

function integer(value) {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function asRecord(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value;
}
