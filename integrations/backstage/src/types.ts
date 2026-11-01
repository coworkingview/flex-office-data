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

/** One Price Index row: a city and a product. */
export type RateRow = {
  citySlug: string;
  cityName: string;
  countryCode: string | null;
  currency: string;
  product: string;
  unit: string | null;
  median: number;
  medianCurrency: string;
  p25: number | null;
  p75: number | null;
  sampleSize: number;
  propertyCount: number | null;
  operatorCount: number | null;
  lowConfidence: boolean;
  asOf: string | null;
};

/** `GET /v1/market/rates` for one city. */
export type RatesResult = {
  rows: RateRow[];
  attribution: string | null;
  /** `data.licenseUrl`. */
  license: string | null;
  asOf: string | null;
};

/** One catalogue row from `GET /v1/properties`. Photos, logos and descriptions are omitted. */
export type SpaceRow = {
  slug: string;
  title: string;
  zoneName: string | null;
  operatorName: string | null;
  fromPrice: number | null;
  fromCurrency: string | null;
  fromBillingPeriod: string | null;
  marketVerdict: string | null;
  marketMedian: number | null;
  marketMedianCurrency: string | null;
  marketSampleSize: number | null;
  url: string | null;
  featured: boolean;
};

/** One page of spaces, plus the citation and catalogue notice from `meta`. */
export type SpacesResult = {
  rows: SpaceRow[];
  total: number | null;
  citation: string | null;
  notice: string | null;
};

export type CitySnapshot = {
  city: string;
  rates: RatesResult;
  spaces: SpacesResult;
};
