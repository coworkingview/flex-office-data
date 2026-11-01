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

import { InfoCard, Progress } from '@backstage/core-components';
import { configApiRef, fetchApiRef, useApi } from '@backstage/core-plugin-api';
import { FormEvent, useEffect, useMemo, useState } from 'react';
import { loadCity, PUBLIC_API } from '../api';
import { isCitySlug, productLabel } from '../parse';
import { CitySnapshot, RateRow, SpaceRow } from '../types';

const tableStyle = {
  width: '100%',
  borderCollapse: 'collapse' as const,
};

const cellStyle = {
  textAlign: 'left' as const,
  padding: '8px 12px',
  borderBottom: '1px solid rgba(127, 127, 127, 0.35)',
  verticalAlign: 'top' as const,
};

const noteStyle = {
  marginTop: 12,
  fontSize: '0.85rem',
};

/** City prices and spaces. Reads `coworkingview.defaultCity` from app-config. */
export const CoworkingViewCard = () => {
  const config = useApi(configApiRef);
  const fetchApi = useApi(fetchApiRef);
  const configuredCity = config.getOptionalString('coworkingview.defaultCity') ?? 'berlin';
  const baseUrl = config.getOptionalString('coworkingview.baseUrl');
  const [city, setCity] = useState(configuredCity);
  const [draft, setDraft] = useState(configuredCity);
  const [snapshot, setSnapshot] = useState<CitySnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchImpl = useMemo(() => {
    const normalized = baseUrl?.trim().replace(/\/$/, '');
    if (!normalized || normalized === PUBLIC_API) {
      return globalThis.fetch.bind(globalThis);
    }
    return fetchApi.fetch.bind(fetchApi);
  }, [baseUrl, fetchApi]);

  useEffect(() => {
    const slug = city.trim().toLowerCase();
    if (!isCitySlug(slug)) {
      setLoading(false);
      setSnapshot(null);
      setError('Enter a city slug such as berlin.');
      return undefined;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);
    loadCity(slug, { baseUrl, fetchImpl })
      .then(result => {
        if (!cancelled) {
          setSnapshot(result);
          setLoading(false);
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setSnapshot(null);
          setError(err instanceof Error ? err.message : 'Request failed');
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [city, baseUrl, fetchImpl]);

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setCity(draft.trim().toLowerCase());
  };

  const cityName = snapshot?.rates.rows[0]?.cityName;
  const title = cityName ?? 'Flexible workspaces';

  return (
    <InfoCard title={title} subheader="CoworkingView Price Index and spaces">
      <form onSubmit={onSubmit} style={{ display: 'flex', gap: 8, alignItems: 'end', marginBottom: 16 }}>
        <label htmlFor="coworkingview-city">
          City
          <input
            id="coworkingview-city"
            name="city"
            value={draft}
            onChange={event => setDraft(event.target.value)}
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            style={{ display: 'block', marginTop: 4, padding: '6px 8px', minWidth: 180 }}
          />
        </label>
        <button type="submit" style={{ padding: '6px 12px' }}>
          Show
        </button>
      </form>
      {loading ? <Progress /> : null}
      {error ? <p role="alert">{error}</p> : null}
      {snapshot && !loading ? <SnapshotView snapshot={snapshot} /> : null}
    </InfoCard>
  );
};

function SnapshotView({ snapshot }: { snapshot: CitySnapshot }) {
  const { rates, spaces, city } = snapshot;
  const listed = spaces.total === null ? String(spaces.rows.length) : String(spaces.total);
  return (
    <>
      <h3>Prices</h3>
      {rates.asOf ? <p>As of {rates.asOf}</p> : null}
      {rates.rows.length === 0 ? (
        <p>No published Price Index figures for this city.</p>
      ) : (
        <table aria-label="Price Index" style={tableStyle}>
          <thead>
            <tr>
              <th style={cellStyle}>Product</th>
              <th style={cellStyle}>Median</th>
              <th style={cellStyle}>25th</th>
              <th style={cellStyle}>75th</th>
              <th style={cellStyle}>Sample</th>
            </tr>
          </thead>
          <tbody>
            {rates.rows.map(row => (
              <RateTableRow key={row.product} row={row} />
            ))}
          </tbody>
        </table>
      )}
      {rates.attribution ? <p style={noteStyle}>{rates.attribution}</p> : null}
      {rates.license ? (
        <p style={noteStyle}>
          <a href={rates.license}>CC BY 4.0</a>
        </p>
      ) : null}

      <h3>Spaces</h3>
      <p>
        {spaces.total === null
          ? `Showing ${spaces.rows.length} spaces.`
          : `Showing ${spaces.rows.length} of ${listed} spaces.`}
      </p>
      {spaces.rows.length === 0 ? (
        <p>No spaces published for this city.</p>
      ) : (
        <table aria-label="Spaces" style={tableStyle}>
          <thead>
            <tr>
              <th style={cellStyle}>Space</th>
              <th style={cellStyle}>Area</th>
              <th style={cellStyle}>Operator</th>
              <th style={cellStyle}>From</th>
              <th style={cellStyle}>Market</th>
            </tr>
          </thead>
          <tbody>
            {spaces.rows.map(row => (
              <SpaceTableRow key={row.slug} row={row} />
            ))}
          </tbody>
        </table>
      )}
      {spaces.citation ? <p style={noteStyle}>{spaces.citation}</p> : null}
      {spaces.notice ? <p style={noteStyle}>{spaces.notice}</p> : null}
      <p style={noteStyle}>
        <a href={`https://coworkingview.com/en/coworking/${city}`}>Coworking in this city</a>
        {' · '}
        <a href={`https://coworkingview.com/en/office-space/${city}`}>Offices in this city</a>
        {' · '}
        <a href="https://coworkingview.com">coworkingview.com</a>
      </p>
    </>
  );
}

function RateTableRow({ row }: { row: RateRow }) {
  const unit = row.unit ? ` / ${row.unit}` : '';
  return (
    <tr>
      <th scope="row" style={cellStyle}>
        {productLabel(row.product)}
        {row.lowConfidence ? ' (low sample)' : ''}
      </th>
      <td style={cellStyle}>
        {formatMoney(row.median, row.medianCurrency)}
        {unit}
      </td>
      <td style={cellStyle}>{row.p25 === null ? '—' : formatMoney(row.p25, row.medianCurrency)}</td>
      <td style={cellStyle}>{row.p75 === null ? '—' : formatMoney(row.p75, row.medianCurrency)}</td>
      <td style={cellStyle}>{row.sampleSize}</td>
    </tr>
  );
}

function SpaceTableRow({ row }: { row: SpaceRow }) {
  const from = formatFromPrice(row);
  const market = formatMarket(row);
  return (
    <tr>
      <th scope="row" style={cellStyle}>
        {row.url ? <a href={row.url}>{row.title}</a> : row.title}
        {row.featured ? ' (featured)' : ''}
      </th>
      <td style={cellStyle}>{row.zoneName ?? '—'}</td>
      <td style={cellStyle}>{row.operatorName ?? '—'}</td>
      <td style={cellStyle}>{from}</td>
      <td style={cellStyle}>{market}</td>
    </tr>
  );
}

function formatFromPrice(row: SpaceRow): string {
  if (row.fromPrice === null || row.fromCurrency === null) {
    return '—';
  }
  const amount = formatMoney(row.fromPrice, row.fromCurrency);
  return row.fromBillingPeriod ? `${amount} / ${row.fromBillingPeriod}` : amount;
}

function formatMarket(row: SpaceRow): string {
  if (row.marketVerdict === null) {
    return '—';
  }
  if (row.marketMedian === null || row.marketMedianCurrency === null) {
    return row.marketVerdict;
  }
  return `${row.marketVerdict}, median ${formatMoney(row.marketMedian, row.marketMedianCurrency)}`;
}

function formatMoney(amount: number, currency: string): string {
  return `${String(amount)} ${currency}`;
}
