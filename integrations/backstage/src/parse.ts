/*
 * Copyright 2026 CoworkingView
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { RateRow, RatesResult, SpacesResult } from './types';

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

const TOP_LEVEL_UNIT: Record<string, string | null> = {
  day_pass: 'day',
  meeting_room: 'hour',
  event_space: 'hour',
  virtual_office: 'month',
};

const LISTING_SEGMENT: Record<string, string> = {
  en: 'workspace',
  es: 'oficina',
  de: 'buero',
};

const SLUG = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function isCitySlug(value: string): boolean {
  return SLUG.test(value);
}

export function productLabel(product: string): string {
  return PRODUCT_LABELS[product] ?? product;
}

type Money = {
  amount: number;
  currency: string;
};

type Stat = {
  median: Money;
  p25: Money | null;
  p75: Money | null;
  sampleSize: number;
  propertyCount: number | null;
  operatorCount: number | null;
};

/**
 * Price Index rows for one city slug.
 * Monthly products come from `figures` when that array is non-empty, otherwise
 * from `byType`. Other aggregates are top-level objects that have `median`
 * and `sampleSize` (`dayPass`, `meetingRoom`, and any later key of that shape).
 */
export function parseRates(body: unknown, citySlug: string): RatesResult {
  const data = asRecord(asRecord(body)?.data);
  const asOf = typeof data?.asOf === 'string' ? data.asOf : null;
  const result: RatesResult = {
    rows: [],
    attribution: typeof data?.attribution === 'string' ? data.attribution : null,
    license: typeof data?.licenseUrl === 'string' ? data.licenseUrl : null,
    asOf,
  };
  if (!data || !Array.isArray(data.cities)) {
    return result;
  }

  for (const item of data.cities) {
    const cityRecord = asRecord(item);
    const city = asRecord(cityRecord?.city);
    if (!cityRecord || city?.slug !== citySlug || typeof city.name !== 'string') {
      continue;
    }
    const countryCode =
      typeof cityRecord.countryCode === 'string' ? cityRecord.countryCode : null;
    const currency = typeof cityRecord.currency === 'string' ? cityRecord.currency : '';
    const rows: RateRow[] = [];

    const figures = Array.isArray(cityRecord.figures) ? cityRecord.figures : [];
    const monthly = figures.length > 0 ? figures : cityRecord.byType;
    if (Array.isArray(monthly)) {
      for (const figure of monthly) {
        const record = asRecord(figure);
        const product = record?.optionType;
        const stat = readStat(figure);
        if (typeof product !== 'string' || !stat) {
          continue;
        }
        rows.push(
          toRow({
            citySlug,
            cityName: city.name,
            countryCode,
            currency,
            product,
            unit: 'month',
            stat,
            asOf,
          }),
        );
      }
    }

    for (const [key, value] of Object.entries(cityRecord)) {
      const stat = readStat(value);
      if (!stat) {
        continue;
      }
      const product = camelToSnake(key);
      rows.push(
        toRow({
          citySlug,
          cityName: city.name,
          countryCode,
          currency,
          product,
          unit: unitForTopLevel(product),
          stat,
          asOf,
        }),
      );
    }

    rows.sort((left, right) => compareProducts(left.product, right.product));
    result.rows.push(...rows);
  }

  return result;
}

/**
 * One page of `GET /v1/properties`.
 * Listing photos, logos and description text are not copied onto the result.
 */
export function parseSpaces(body: unknown, locale = 'en'): SpacesResult {
  const root = asRecord(body);
  const meta = asRecord(root?.meta);
  const pagination = asRecord(meta?.pagination);
  const citation = asRecord(meta?.citation);
  const total = pagination?.total;
  const result: SpacesResult = {
    rows: [],
    total: typeof total === 'number' && Number.isInteger(total) && total >= 0 ? total : null,
    citation: typeof citation?.text === 'string' ? citation.text : null,
    notice: typeof meta?.catalogueNotice === 'string' ? meta.catalogueNotice : null,
  };
  if (!Array.isArray(root?.data)) {
    return result;
  }

  for (const item of root.data) {
    const record = asRecord(item);
    if (!record || typeof record.slug !== 'string' || typeof record.title !== 'string') {
      continue;
    }
    const zone = asRecord(record.zone);
    const operator = asRecord(record.operator);
    const fromPrice = readMoney(record.fromPrice);
    const market = asRecord(record.marketPosition);
    const marketMedian = readMoney(market?.median);
    const marketSample = market?.sampleSize;
    result.rows.push({
      slug: record.slug,
      title: record.title,
      zoneName: typeof zone?.name === 'string' ? zone.name : null,
      operatorName: typeof operator?.name === 'string' ? operator.name : null,
      fromPrice: fromPrice?.amount ?? null,
      fromCurrency: fromPrice?.currency ?? null,
      fromBillingPeriod:
        typeof record.fromBillingPeriod === 'string' ? record.fromBillingPeriod : null,
      marketVerdict: typeof market?.verdict === 'string' ? market.verdict : null,
      marketMedian: marketMedian?.amount ?? null,
      marketMedianCurrency: marketMedian?.currency ?? null,
      marketSampleSize:
        typeof marketSample === 'number' && Number.isFinite(marketSample) ? marketSample : null,
      url: listingUrl(locale, record.slug),
      featured: record.featured === true,
    });
  }

  return result;
}

export function listingUrl(locale: string, slug: string): string | null {
  const segment = LISTING_SEGMENT[locale];
  if (!segment || !SLUG.test(slug)) {
    return null;
  }
  return `https://coworkingview.com/${locale}/${segment}/${slug}`;
}

function toRow(input: {
  citySlug: string;
  cityName: string;
  countryCode: string | null;
  currency: string;
  product: string;
  unit: string | null;
  stat: Stat;
  asOf: string | null;
}): RateRow {
  return {
    citySlug: input.citySlug,
    cityName: input.cityName,
    countryCode: input.countryCode,
    currency: input.currency,
    product: input.product,
    unit: input.unit,
    median: input.stat.median.amount,
    medianCurrency: input.stat.median.currency,
    p25: input.stat.p25?.amount ?? null,
    p75: input.stat.p75?.amount ?? null,
    sampleSize: input.stat.sampleSize,
    propertyCount: input.stat.propertyCount,
    operatorCount: input.stat.operatorCount,
    lowConfidence: input.stat.sampleSize < 10,
    asOf: input.asOf,
  };
}

function unitForTopLevel(product: string): string | null {
  if (Object.prototype.hasOwnProperty.call(TOP_LEVEL_UNIT, product)) {
    return TOP_LEVEL_UNIT[product];
  }
  return null;
}

function compareProducts(left: string, right: string): number {
  const leftRank = PRODUCT_ORDER.indexOf(left);
  const rightRank = PRODUCT_ORDER.indexOf(right);
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
  return left.localeCompare(right);
}

function readStat(value: unknown): Stat | null {
  const record = asRecord(value);
  const median = readMoney(record?.median);
  const sampleSize = record?.sampleSize;
  if (!median || typeof sampleSize !== 'number' || !Number.isFinite(sampleSize)) {
    return null;
  }
  return {
    median,
    p25: readMoney(record?.p25),
    p75: readMoney(record?.p75),
    sampleSize,
    propertyCount: finiteNumber(record?.propertyCount),
    operatorCount: finiteNumber(record?.operatorCount),
  };
}

function readMoney(value: unknown): Money | null {
  const record = asRecord(value);
  const amount = record?.amount;
  const currency = record?.currency;
  if (typeof amount !== 'number' || !Number.isFinite(amount)) {
    return null;
  }
  if (typeof currency !== 'string' || currency.length === 0) {
    return null;
  }
  return { amount, currency };
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function camelToSnake(key: string): string {
  return key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}
