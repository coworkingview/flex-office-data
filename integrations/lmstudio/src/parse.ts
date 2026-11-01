/**
 * Reads public CoworkingView JSON the way the other clients in this repository do.
 * Field names below are the ones those clients already read. Nothing else is filled in.
 */

export const API_ORIGIN = "https://api.coworkingview.com";
export const HOMEPAGE = "https://coworkingview.com";
export const ATTRIBUTION_TEXT = "Data: CoworkingView (https://coworkingview.com)";

export const PRODUCTS = [
  "flex_desk",
  "fix_desk",
  "private_office",
  "exclusive_bereich",
  "day_pass",
  "meeting_room",
  "event_space",
  "virtual_office",
  "membership",
] as const;

export type Product = (typeof PRODUCTS)[number];

export const LOCALES = ["en", "de", "es"] as const;
export type Locale = (typeof LOCALES)[number];

const LISTING_SEGMENT: Record<Locale, string> = {
  en: "workspace",
  es: "oficina",
  de: "buero",
};

const TOP_LEVEL_UNIT: Record<string, string | null> = {
  day_pass: "day",
  meeting_room: "hour",
  event_space: "hour",
  virtual_office: "month",
};

const SLUG = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export const PAGE_SIZE = 10;

export class InputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InputError";
  }
}

export function normalizeCity(value: string): string {
  const slug = value.trim().toLowerCase().replace(/[\s_]+/g, "-");
  if (!SLUG.test(slug)) {
    throw new InputError(
      "city must be a CoworkingView city slug such as berlin or abu-dhabi. Call list_cities for the published slugs.",
    );
  }
  return slug;
}

export function normalizeLocale(value: string | undefined, fallback: Locale): Locale {
  if (value === undefined || value === "") {
    return fallback;
  }
  if (value === "en" || value === "de" || value === "es") {
    return value;
  }
  throw new InputError("language must be en, de, or es.");
}

export function normalizeProduct(value: string | undefined): Product | null {
  if (value === undefined || value === "") {
    return null;
  }
  if ((PRODUCTS as readonly string[]).includes(value)) {
    return value as Product;
  }
  throw new InputError(`product must be one of: ${PRODUCTS.join(", ")}.`);
}

export type PriceRow = {
  product: string;
  unit: string | null;
  median: number;
  currency: string | null;
  p25: number | null;
  p75: number | null;
  sample_size: number | null;
  low_confidence: boolean;
};

export type RatesMeta = {
  as_of: string | null;
  attribution: string | null;
  license: string | null;
  license_url: string | null;
  attribution_text: typeof ATTRIBUTION_TEXT;
  link: typeof HOMEPAGE;
};

export type PriceSnapshot = RatesMeta & {
  city_slug: string;
  city_name: string;
  country_code: string | null;
  currency: string | null;
  prices: PriceRow[];
};

export type CityRow = {
  slug: string;
  name: string;
  country_code: string | null;
  currency: string | null;
  property_count: number | null;
  operator_count: number | null;
  sample_size: number | null;
};

export type CityList = RatesMeta & {
  cities: CityRow[];
};

export type WorkspaceRow = {
  slug: string;
  title: string;
  city_slug: string | null;
  zone_slug: string | null;
  operator_slug: string | null;
  operator_name: string | null;
  country_code: string | null;
  lat: number | null;
  lng: number | null;
  featured: boolean | null;
  market_verdict: string | null;
  market_median: number | null;
  market_currency: string | null;
  market_sample_size: number | null;
  url: string;
  updated_at: string | null;
};

export type WorkspaceSearch = {
  workspaces: WorkspaceRow[];
  total: number | null;
  citation: string | null;
  notice: string | null;
  attribution_text: typeof ATTRIBUTION_TEXT;
  link: typeof HOMEPAGE;
};

type Money = { amount: number; currency: string | null };

export function listingUrl(locale: Locale, slug: string): string {
  return `${HOMEPAGE}/${locale}/${LISTING_SEGMENT[locale]}/${slug}`;
}

export function parsePrices(
  body: unknown,
  citySlug: string,
  product: Product | null,
): { ok: true; snapshot: PriceSnapshot } | { ok: false; message: string } {
  const data = asRecord(asRecord(body)?.data);
  if (!data || !Array.isArray(data.cities)) {
    return { ok: false, message: "Error: The CoworkingView API response has no cities list." };
  }

  const wanted = citySlug.toLowerCase();
  const found = data.cities.find(item => citySlugOf(item) === wanted);
  const city = asRecord(found);
  if (!city) {
    if (unpublishedSlug(data, wanted)) {
      return {
        ok: false,
        message: `Error: "${citySlug}" is not a published CoworkingView city. Call list_cities for published slugs.`,
      };
    }
    return {
      ok: false,
      message: `Error: No published city "${citySlug}" in the CoworkingView Price Index. Call list_cities for published slugs.`,
    };
  }

  const info = asRecord(city.city);
  const cityName = typeof info?.name === "string" && info.name.length > 0 ? info.name : citySlug;
  const rows = rowsForCity(city);
  const selected = product === null ? rows : rows.filter(row => row.product === product);
  if (product !== null && selected.length === 0) {
    const published = rows.map(row => row.product);
    const list = published.length > 0 ? published.join(", ") : "none";
    return {
      ok: false,
      message: `Error: ${cityName} does not publish "${product}" in this Price Index response. Published products: ${list}.`,
    };
  }

  return {
    ok: true,
    snapshot: {
      city_slug: citySlugOf(city) || citySlug,
      city_name: cityName,
      country_code: optionalString(city.countryCode),
      currency: optionalString(city.currency),
      prices: selected,
      ...ratesMeta(data),
    },
  };
}

export function parseCities(body: unknown): { ok: true; list: CityList } | { ok: false; message: string } {
  const data = asRecord(asRecord(body)?.data);
  if (!data || !Array.isArray(data.cities)) {
    return { ok: false, message: "Error: The CoworkingView API response has no cities list." };
  }

  const cities: CityRow[] = [];
  for (const item of data.cities) {
    const city = asRecord(item);
    const info = asRecord(city?.city);
    const slug = typeof info?.slug === "string" ? info.slug : "";
    const name = typeof info?.name === "string" ? info.name : "";
    if (!city || !SLUG.test(slug) || name.length === 0) {
      continue;
    }
    cities.push({
      slug,
      name,
      country_code: optionalString(city.countryCode),
      currency: optionalString(city.currency),
      property_count: wholeNumber(city.propertyCount),
      operator_count: wholeNumber(city.operatorCount),
      sample_size: wholeNumber(city.sampleSize),
    });
  }
  cities.sort((left, right) => (left.slug < right.slug ? -1 : left.slug > right.slug ? 1 : 0));

  return { ok: true, list: { cities, ...ratesMeta(data) } };
}

export function parseWorkspaces(
  body: unknown,
  locale: Locale,
): { ok: true; search: WorkspaceSearch } | { ok: false; message: string } {
  const root = asRecord(body);
  if (!root || !Array.isArray(root.data)) {
    return { ok: false, message: "Error: The CoworkingView API response has no listings." };
  }
  const meta = asRecord(root.meta);
  const pagination = asRecord(meta?.pagination);
  const citation = asRecord(meta?.citation);
  const workspaces: WorkspaceRow[] = [];

  for (const item of root.data) {
    const record = asRecord(item);
    if (!record || typeof record.slug !== "string" || !SLUG.test(record.slug)) {
      continue;
    }
    if (typeof record.title !== "string" || record.title.length === 0) {
      continue;
    }
    const city = asRecord(record.city);
    const zone = asRecord(record.zone);
    const operator = asRecord(record.operator);
    const coordinates = asRecord(record.coordinates);
    const market = asRecord(record.marketPosition);
    const median = readMoney(market?.median);
    const sample = market?.sampleSize;
    workspaces.push({
      slug: record.slug,
      title: record.title,
      city_slug: typeof city?.slug === "string" ? city.slug : null,
      zone_slug: typeof zone?.slug === "string" ? zone.slug : null,
      operator_slug: typeof operator?.slug === "string" ? operator.slug : null,
      operator_name: typeof operator?.name === "string" ? operator.name : null,
      country_code: optionalString(record.countryCode),
      lat: finiteNumber(coordinates?.lat),
      lng: finiteNumber(coordinates?.lng),
      featured: typeof record.featured === "boolean" ? record.featured : null,
      market_verdict: typeof market?.verdict === "string" ? market.verdict : null,
      market_median: median?.amount ?? null,
      market_currency: median?.currency ?? null,
      market_sample_size: typeof sample === "number" && Number.isFinite(sample) ? sample : null,
      url: listingUrl(locale, record.slug),
      updated_at: typeof record.updatedAt === "string" ? record.updatedAt : null,
    });
  }

  return {
    ok: true,
    search: {
      workspaces,
      total: wholeNumber(pagination?.total),
      citation: typeof citation?.text === "string" ? citation.text : null,
      notice: typeof meta?.catalogueNotice === "string" ? meta.catalogueNotice : null,
      attribution_text: ATTRIBUTION_TEXT,
      link: HOMEPAGE,
    },
  };
}

function ratesMeta(data: Record<string, unknown>): RatesMeta {
  return {
    as_of: optionalString(data.asOf),
    attribution: optionalString(data.attribution),
    license: optionalString(data.license),
    license_url: httpsUrl(optionalString(data.licenseUrl)),
    attribution_text: ATTRIBUTION_TEXT,
    link: HOMEPAGE,
  };
}

function rowsForCity(city: Record<string, unknown>): PriceRow[] {
  const figures = Array.isArray(city.figures) ? city.figures : [];
  const monthly = figures.length > 0 ? figures : Array.isArray(city.byType) ? city.byType : [];
  const currency = optionalString(city.currency);
  const rows: PriceRow[] = [];

  for (const item of monthly) {
    const record = asRecord(item);
    const product = record?.optionType;
    if (!record || typeof product !== "string" || product.length === 0) {
      continue;
    }
    const row = rowFromStat(record, product, "month", currency);
    if (row) {
      rows.push(row);
    }
  }

  for (const [key, value] of Object.entries(city)) {
    const record = asRecord(value);
    if (!record || !("median" in record) || !("sampleSize" in record)) {
      continue;
    }
    const product = camelToSnake(key);
    const unit = Object.prototype.hasOwnProperty.call(TOP_LEVEL_UNIT, product)
      ? TOP_LEVEL_UNIT[product]
      : null;
    const row = rowFromStat(record, product, unit, currency);
    if (row) {
      rows.push(row);
    }
  }

  rows.sort((left, right) => compareProducts(left.product, right.product));
  return rows;
}

function rowFromStat(
  record: Record<string, unknown>,
  product: string,
  unit: string | null,
  cityCurrency: string | null,
): PriceRow | null {
  const median = readMoney(record.median);
  if (!median) {
    return null;
  }
  const sample = wholeNumber(record.sampleSize);
  return {
    product,
    unit,
    median: median.amount,
    currency: median.currency ?? cityCurrency,
    p25: readMoney(record.p25)?.amount ?? null,
    p75: readMoney(record.p75)?.amount ?? null,
    sample_size: sample,
    low_confidence: sample !== null && sample < 10,
  };
}

function compareProducts(left: string, right: string): number {
  const leftRank = PRODUCTS.indexOf(left as Product);
  const rightRank = PRODUCTS.indexOf(right as Product);
  const leftKnown = leftRank !== -1;
  const rightKnown = rightRank !== -1;
  if (leftKnown && rightKnown) {
    return leftRank - rightRank;
  }
  if (leftKnown) {
    return -1;
  }
  if (rightKnown) {
    return 1;
  }
  return left < right ? -1 : left > right ? 1 : 0;
}

function unpublishedSlug(data: Record<string, unknown>, wanted: string): boolean {
  if (!Array.isArray(data.unpublished)) {
    return false;
  }
  return data.unpublished.some(item => citySlugOf(item) === wanted);
}

function citySlugOf(value: unknown): string {
  const city = asRecord(asRecord(value)?.city);
  return typeof city?.slug === "string" ? city.slug.toLowerCase() : "";
}

function readMoney(value: unknown): Money | null {
  const record = asRecord(value);
  const amount = record?.amount;
  if (typeof amount !== "number" || !Number.isFinite(amount)) {
    return null;
  }
  const currency = record?.currency;
  return {
    amount,
    currency: typeof currency === "string" && currency.length > 0 ? currency : null,
  };
}

function wholeNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return null;
  }
  return value;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function httpsUrl(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? value : null;
  } catch {
    return null;
  }
}

function camelToSnake(key: string): string {
  return key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}
