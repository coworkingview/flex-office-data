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

import { ConfigReader } from '@backstage/config';
import { configApiRef } from '@backstage/core-plugin-api';
import { renderInTestApp, TestApiProvider } from '@backstage/test-utils';
import { fireEvent, screen } from '@testing-library/react';
import { PUBLIC_API } from '../api';
import errorValidation from '../fixtures/error_validation.json';
import marketRates from '../fixtures/market_rates.json';
import propertiesBerlin from '../fixtures/properties_berlin.json';
import { CoworkingViewPage } from './CoworkingViewPage';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function installFetch() {
  const fetchMock = jest.fn(async (input: RequestInfo | URL) => {
    const url = new URL(String(input));
    expect(url.host).toBe('api.coworkingview.com');
    if (url.pathname === '/v1/market/rates') {
      expect(url.searchParams.get('locale')).toBe('en');
      return jsonResponse(marketRates);
    }
    if (url.pathname === '/v1/properties') {
      expect(url.searchParams.get('locale')).toBe('en');
      expect(url.searchParams.get('page')).toBe('1');
      expect(url.searchParams.get('pageSize')).toBe('10');
      if (url.searchParams.get('city') !== 'berlin') {
        return jsonResponse({
          data: [],
          meta: {
            pagination: { page: 1, pageSize: 10, total: 0, pageCount: 0 },
            citation: { text: 'Source: CoworkingView.' },
            catalogueNotice: propertiesBerlin.meta.catalogueNotice,
          },
        });
      }
      return jsonResponse(propertiesBerlin);
    }
    throw new Error(`unexpected url ${url.toString()}`);
  });
  global.fetch = fetchMock as typeof fetch;
  return fetchMock;
}

async function renderPage(defaultCity = 'berlin') {
  return renderInTestApp(
    <TestApiProvider
      apis={[[configApiRef, new ConfigReader({ coworkingview: { defaultCity } })]]}
    >
      <CoworkingViewPage />
    </TestApiProvider>,
  );
}

describe('CoworkingViewPage', () => {
  let fetchMock: ReturnType<typeof installFetch>;

  beforeEach(() => {
    fetchMock = installFetch();
  });

  it('shows fixture prices and spaces for the configured city without catalogue media', async () => {
    await renderPage();

    expect(await screen.findByRole('rowheader', { name: 'Flex desk' })).toBeInTheDocument();
    expect(screen.getByRole('cell', { name: '214 EUR / month' })).toBeInTheDocument();
    expect(screen.getByRole('cell', { name: '35 EUR / day' })).toBeInTheDocument();
    expect(screen.getByRole('cell', { name: '32 EUR / hour' })).toBeInTheDocument();
    expect(screen.getByText(/Licensed under CC BY 4.0/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'CC BY 4.0' })).toHaveAttribute(
      'href',
      'https://creativecommons.org/licenses/by/4.0/',
    );
    expect(
      screen.getByRole('link', {
        name: 'St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße',
      }),
    ).toHaveAttribute(
      'href',
      'https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin',
    );
    expect(screen.getByRole('cell', { name: '750 EUR / month' })).toBeInTheDocument();
    expect(screen.getByText(/Systematic extraction/)).toBeInTheDocument();
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
    expect(screen.queryByText(/example.com/)).not.toBeInTheDocument();
    expect(screen.queryByText(/CoWoS Berlin/)).not.toBeInTheDocument();
    expect(screen.getByLabelText('City')).toHaveValue('berlin');

    const urls = fetchMock.mock.calls.map(call => String(call[0]));
    expect(urls).toEqual([
      `${PUBLIC_API}/v1/market/rates?locale=en&city=berlin`,
      `${PUBLIC_API}/v1/properties?locale=en&city=berlin&page=1&pageSize=10`,
    ]);
  });

  it('uses coworkingview.defaultCity and requests that slug', async () => {
    await renderPage('madrid');

    expect(await screen.findByRole('cell', { name: '175 EUR / month' })).toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Dedicated desk (low sample)' })).toBeInTheDocument();
    expect(screen.getByText('No spaces published for this city.')).toBeInTheDocument();
    const urls = fetchMock.mock.calls.map(call => String(call[0]));
    expect(urls.some(url => url.includes('city=madrid'))).toBe(true);
    expect(urls.every(url => url.startsWith(PUBLIC_API))).toBe(true);
  });

  it('shows the API problem detail and does not fetch an invalid slug', async () => {
    fetchMock.mockImplementation(async () => jsonResponse(errorValidation, 400));
    await renderPage();

    expect(await screen.findByRole('alert')).toHaveTextContent(errorValidation.detail);
    const callsAfterError = fetchMock.mock.calls.length;

    const input = screen.getByLabelText('City');
    fireEvent.change(input, { target: { value: 'Berlin!' } });
    fireEvent.click(screen.getByRole('button', { name: 'Show' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Enter a city slug such as berlin.');
    expect(fetchMock.mock.calls.length).toBe(callsAfterError);
  });
});
