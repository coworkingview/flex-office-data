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

import marketRates from '../src/fixtures/market_rates.json';
import propertiesBerlin from '../src/fixtures/properties_berlin.json';

/** Serve the checked-in API fixtures for `/v1/market/rates` and `/v1/properties`. */
export function installFixtureFetch(): void {
  const original = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = requestUrl(input);
    if (url.includes('/v1/market/rates')) {
      return json(marketRates);
    }
    if (url.includes('/v1/properties')) {
      return json(propertiesBerlin);
    }
    return original(input, init);
  };
}

function requestUrl(input: RequestInfo | URL): string {
  if (typeof input === 'string') {
    return input;
  }
  if (input instanceof URL) {
    return input.toString();
  }
  return input.url;
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
