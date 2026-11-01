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

import marketRates from './fixtures/market_rates.json';
import propertiesBerlin from './fixtures/properties_berlin.json';
import { parseRates, parseSpaces } from './parse';

describe('parseRates', () => {
  it('reads Berlin figures, day pass and meeting room in Price Index order', () => {
    const result = parseRates(marketRates, 'berlin');

    expect(result.asOf).toBe('2026-10-27T21:06:48.313Z');
    expect(result.license).toBe('https://creativecommons.org/licenses/by/4.0/');
    expect(result.attribution).toContain('CC BY 4.0');
    expect(result.rows.map(row => row.product)).toEqual([
      'flex_desk',
      'fix_desk',
      'private_office',
      'day_pass',
      'meeting_room',
    ]);
    expect(result.rows.map(row => [row.median, row.p25, row.p75, row.sampleSize, row.unit, row.lowConfidence])).toEqual([
      [214, 199, 292, 72, 'month', false],
      [310, 290, 421, 60, 'month', false],
      [480, 399, 550, 59, 'month', false],
      [35, null, null, 59, 'day', false],
      [32, null, null, 79, 'hour', false],
    ]);
    expect(result.rows[0]).toMatchObject({
      citySlug: 'berlin',
      cityName: 'Berlin',
      countryCode: 'DE',
      currency: 'EUR',
      medianCurrency: 'EUR',
      propertyCount: 66,
      operatorCount: 38,
    });
  });

  it('marks a sample under 10 as low confidence and skips unpublished cities', () => {
    const madrid = parseRates(marketRates, 'madrid');
    const fixDesk = madrid.rows.find(row => row.product === 'fix_desk');
    expect(fixDesk).toMatchObject({ median: 260, sampleSize: 9, lowConfidence: true });

    const unpublished = parseRates(marketRates, 'example-town');
    expect(unpublished.rows).toEqual([]);
    expect(unpublished.attribution).toContain('CoworkingView Price Index');
  });

  it('prefers figures over byType when both are present', () => {
    const body = {
      data: {
        asOf: '2026-10-27T21:06:48.313Z',
        attribution: 'Source: CoworkingView Price Index',
        licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
        cities: [
          {
            city: { slug: 'berlin', name: 'Berlin' },
            countryCode: 'DE',
            currency: 'EUR',
            byType: [
              {
                optionType: 'flex_desk',
                median: { amount: 1, currency: 'EUR' },
                sampleSize: 72,
              },
            ],
            figures: [
              {
                optionType: 'flex_desk',
                median: { amount: 214, currency: 'EUR' },
                p25: { amount: 199, currency: 'EUR' },
                p75: { amount: 292, currency: 'EUR' },
                sampleSize: 72,
                propertyCount: 66,
                operatorCount: 38,
              },
            ],
          },
        ],
      },
    };

    expect(parseRates(body, 'berlin').rows.map(row => row.median)).toEqual([214]);
  });
});

describe('parseSpaces', () => {
  it('keeps listing fields and drops photos, logos and descriptions', () => {
    const result = parseSpaces(propertiesBerlin, 'en');

    expect(result.total).toBe(110);
    expect(result.citation).toContain('https://coworkingview.com/en/coworking/berlin');
    expect(result.notice).toContain('Systematic extraction');
    expect(result.rows.map(row => row.slug)).toEqual([
      'sankt-oberholz-rosenthaler-berlin',
      'smartspaces-berlin-spandau',
      'regus-charlottenburg-berlin',
    ]);
    expect(result.rows[0]).toMatchObject({
      title: 'St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße',
      zoneName: 'Mitte',
      operatorName: 'St. Oberholz',
      fromPrice: null,
      marketVerdict: 'around',
      marketMedian: 214,
      marketMedianCurrency: 'EUR',
      marketSampleSize: 72,
      featured: true,
      url: 'https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin',
    });
    expect(result.rows[1]).toMatchObject({
      fromPrice: 750,
      fromCurrency: 'EUR',
      fromBillingPeriod: 'month',
      featured: false,
    });
    expect(result.rows[2].marketVerdict).toBeNull();

    const encoded = JSON.stringify(result);
    expect(encoded).not.toContain('example.com');
    expect(encoded).not.toContain('excerpt');
    expect(encoded).not.toContain('amenities');
    expect(encoded).not.toContain('https://example.com/logo.png');
  });
});
