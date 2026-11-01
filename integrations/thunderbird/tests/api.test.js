import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { ApiError } from "../addon/lib/errors.js";
import {
  buildPropertiesUrl,
  buildRatesUrl,
  fetchJson,
  loadCities,
  loadReport,
  retryDelayMs,
} from "../addon/lib/http.js";
import {
  httpsUrl,
  isSlug,
  parseCities,
  parseCityRates,
  parseWorkspaceCount,
  uiLocale,
} from "../addon/lib/parse.js";
import { readStoredCity, writeStoredCity } from "../addon/lib/storage.js";

globalThis.fetch = () => {
  throw new Error("network disabled in tests");
};

const ratesBerlin = load("rates-berlin.json");
const ratesCities = load("rates-cities.json");
const propertiesBerlin = load("properties-berlin.json");
const propertiesEmpty = load("properties-empty.json");
const errorValidation = load("error-validation.json");

test("locale and slug follow the API rules", () => {
  assert.equal(uiLocale("de-DE"), "de");
  assert.equal(uiLocale("es"), "es");
  assert.equal(uiLocale("en-US"), "en");
  assert.equal(uiLocale("fr-FR"), "en");
  assert.equal(uiLocale(""), "en");
  assert.equal(isSlug("berlin"), true);
  assert.equal(isSlug("bad-homburg"), true);
  assert.equal(isSlug("Berlin"), true);
  assert.equal(isSlug(""), false);
  assert.equal(isSlug("../v1/market/rates"), false);
  assert.equal(isSlug("berlin/extra"), false);
  assert.equal(isSlug("-berlin"), false);
});

test("rates URL carries locale and city, properties URL asks for one row", () => {
  const rates = new URL(buildRatesUrl("de-AT", "berlin"));
  assert.equal(rates.origin, "https://api.coworkingview.com");
  assert.equal(rates.pathname, "/v1/market/rates");
  assert.equal(rates.searchParams.get("locale"), "de");
  assert.equal(rates.searchParams.get("city"), "berlin");

  const list = new URL(buildRatesUrl("en"));
  assert.equal(list.searchParams.get("city"), null);
  assert.equal(list.searchParams.get("locale"), "en");

  const properties = new URL(buildPropertiesUrl("en", "madrid"));
  assert.equal(properties.pathname, "/v1/properties");
  assert.equal(properties.searchParams.get("locale"), "en");
  assert.equal(properties.searchParams.get("city"), "madrid");
  assert.equal(properties.searchParams.get("page"), "1");
  assert.equal(properties.searchParams.get("pageSize"), "1");
});

test("Berlin fixture maps figures, day pass and meeting room", () => {
  const report = parseCityRates(ratesBerlin, "berlin");
  assert.equal(report.cityName, "Berlin");
  assert.equal(report.currency, "USD");
  assert.equal(report.countryCode, "DE");
  assert.equal(
    report.attribution,
    ratesBerlin.data.attribution,
  );
  assert.equal(report.license, "CC-BY-4.0");
  assert.equal(report.licenseUrl, "https://creativecommons.org/licenses/by/4.0/");
  assert.equal(report.asOf, ratesBerlin.data.asOf);

  const byProduct = Object.fromEntries(report.products.map((row) => [row.product, row]));
  assert.deepEqual(Object.keys(byProduct), [
    "flex_desk",
    "fix_desk",
    "private_office",
    "day_pass",
    "meeting_room",
  ]);
  assert.equal(byProduct.flex_desk.median.amount, 233);
  assert.equal(byProduct.flex_desk.p25.amount, 216);
  assert.equal(byProduct.flex_desk.p75.amount, 317);
  assert.equal(byProduct.flex_desk.sampleSize, 72);
  assert.equal(byProduct.flex_desk.unit, "month");
  assert.equal(byProduct.flex_desk.lowConfidence, false);
  assert.equal(byProduct.day_pass.unit, "day");
  assert.equal(byProduct.day_pass.median.amount, 38);
  assert.equal(byProduct.day_pass.p25, null);
  assert.equal(byProduct.meeting_room.unit, "hour");
  assert.equal(byProduct.meeting_room.median.amount, 35);

  const encoded = JSON.stringify(report);
  assert.equal(encoded.includes("betahaus"), false);
  assert.equal(encoded.includes("MACHWERK"), false);
  assert.equal(encoded.includes("buildings"), false);
});

test("byType fallback drops p25 and p75", () => {
  const body = structuredClone(ratesBerlin);
  delete body.data.cities[0].figures;
  const report = parseCityRates(body, "berlin");
  const flex = report.products.find((row) => row.product === "flex_desk");
  assert.equal(flex.median.amount, 233);
  assert.equal(flex.p25, null);
  assert.equal(flex.p75, null);
  assert.equal(flex.unit, "month");
});

test("a future aggregate with median and sampleSize is kept", () => {
  const body = structuredClone(ratesBerlin);
  body.data.cities[0].eventSpace = {
    median: { amount: 90, currency: "USD" },
    sampleSize: 4,
  };
  const report = parseCityRates(body, "berlin");
  const eventSpace = report.products.find((row) => row.product === "event_space");
  assert.equal(eventSpace.unit, "hour");
  assert.equal(eventSpace.median.amount, 90);
  assert.equal(eventSpace.lowConfidence, true);
});

test("unpublished cities are not selectable and an unknown slug is null", () => {
  const cities = parseCities(ratesCities);
  const slugs = cities.map((city) => city.slug);
  assert.equal(slugs.includes("berlin"), true);
  assert.equal(slugs.includes("abu-dhabi"), true);
  const unpublished = ratesCities.data.unpublished.map((city) => city.city.slug);
  assert.ok(unpublished.length > 0);
  for (const slug of unpublished) {
    assert.equal(slugs.includes(slug), false);
  }
  assert.equal(parseCityRates(ratesCities, unpublished[0]), null);
  assert.deepEqual(
    cities.map((city) => city.name),
    cities.map((city) => city.name).slice().sort((a, b) => a.localeCompare(b, "en")),
  );
});

test("low confidence follows sample size under 10", () => {
  const report = parseCityRates(ratesCities, "abu-dhabi");
  assert.ok(report.products.length > 0);
  assert.ok(report.products.some((row) => row.lowConfidence));
  for (const row of report.products) {
    assert.equal(row.lowConfidence, row.sampleSize !== null && row.sampleSize < 10);
  }
});

test("workspace count is pagination.total, not the listing array", () => {
  const count = parseWorkspaceCount(propertiesBerlin);
  assert.equal(count.total, 110);
  assert.notEqual(count.total, propertiesBerlin.data.length);
  assert.equal(count.citation, propertiesBerlin.meta.citation.text);
  assert.equal(count.citationUrl, propertiesBerlin.meta.citation.url);
  assert.equal(JSON.stringify(count).includes("St. Oberholz"), false);
  assert.equal(parseWorkspaceCount(propertiesEmpty).total, 0);
  assert.equal(parseWorkspaceCount({ data: [], meta: {} }), null);
});

test("only https URLs are kept", () => {
  assert.equal(httpsUrl("https://coworkingview.com/en/privacy"), "https://coworkingview.com/en/privacy");
  assert.equal(httpsUrl("http://coworkingview.com/en/privacy"), null);
  assert.equal(httpsUrl("javascript:alert(1)"), null);
  assert.equal(httpsUrl("not a url"), null);
});

test("fetchJson retries a 429 once and then surfaces the problem", async () => {
  const calls = [];
  const sleeps = [];
  await assert.rejects(
    () =>
      fetchJson("https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin", {
        fetchImpl: async (url, init) => {
          calls.push({ url, init });
          return jsonResponse(429, errorValidation, { "retry-after": "50" });
        },
        sleep: async (ms) => {
          sleeps.push(ms);
        },
      }),
    (error) => {
      assert.ok(error instanceof ApiError);
      assert.equal(error.status, 429);
      assert.equal(error.code, "VALIDATION_FAILED");
      assert.equal(error.message, errorValidation.detail);
      return true;
    },
  );
  assert.equal(calls.length, 2);
  assert.deepEqual(sleeps, [10000]);
  assert.equal(calls[0].init.method, "GET");
  assert.equal(calls[0].init.credentials, "omit");
  assert.equal(calls[0].init.headers.Accept, "application/json");
});

test("fetchJson does not retry a 400", async () => {
  let calls = 0;
  await assert.rejects(
    () =>
      fetchJson("https://api.coworkingview.com/v1/market/rates?locale=en", {
        fetchImpl: async () => {
          calls += 1;
          return jsonResponse(400, errorValidation);
        },
        sleep: async () => {
          throw new Error("should not sleep");
        },
      }),
    (error) => error instanceof ApiError && error.status === 400,
  );
  assert.equal(calls, 1);
});

test("a non-JSON body is BAD_RESPONSE and a 500 is retried once", async () => {
  await assert.rejects(
    () =>
      fetchJson("https://api.coworkingview.com/v1/market/rates?locale=en", {
        fetchImpl: async () => jsonResponse(200, "<html></html>", {}, true),
        sleep: async () => {},
      }),
    (error) => error instanceof ApiError && error.code === "BAD_RESPONSE",
  );

  let calls = 0;
  const body = await fetchJson("https://api.coworkingview.com/v1/properties?locale=en&city=berlin", {
    fetchImpl: async () => {
      calls += 1;
      if (calls === 1) {
        return jsonResponse(503, { title: "Unavailable", status: 503 }, { "ratelimit-reset": "1" });
      }
      return jsonResponse(200, propertiesEmpty);
    },
    sleep: async () => {},
  });
  assert.equal(calls, 2);
  assert.equal(body.meta.pagination.total, 0);
});

test("retry delay prefers Retry-After, then RateLimit-Reset, then 2 seconds", () => {
  assert.equal(retryDelayMs(headers({ "retry-after": "1" })), 1000);
  assert.equal(retryDelayMs(headers({ "retry-after": "99" })), 10000);
  assert.equal(retryDelayMs(headers({ "ratelimit-reset": "3" })), 3000);
  assert.equal(retryDelayMs(headers({ "retry-after": "Thu, 01 Nov 2026 00:00:00 GMT" })), 2000);
  assert.equal(retryDelayMs(headers({})), 2000);
});

test("loadReport uses both endpoints and keeps the attribution verbatim", async () => {
  const urls = [];
  const report = await loadReport("berlin", "en-US", {
    fetchImpl: async (url) => {
      urls.push(url);
      const parsed = new URL(url);
      if (parsed.pathname === "/v1/market/rates") {
        return jsonResponse(200, ratesBerlin);
      }
      return jsonResponse(200, propertiesBerlin);
    },
    sleep: async () => {},
  });
  assert.equal(urls.length, 2);
  assert.equal(new URL(urls[0]).searchParams.get("city"), "berlin");
  assert.equal(new URL(urls[0]).searchParams.get("locale"), "en");
  assert.equal(new URL(urls[1]).pathname, "/v1/properties");
  assert.equal(new URL(urls[1]).searchParams.get("pageSize"), "1");
  assert.equal(report.attribution, ratesBerlin.data.attribution);
  assert.equal(report.workspaceTotal, 110);
  assert.equal(JSON.stringify(report).includes("St. Oberholz"), false);
});

test("loadReport still returns prices when the catalogue request fails", async () => {
  const report = await loadReport("berlin", "en", {
    fetchImpl: async (url) => {
      if (new URL(url).pathname === "/v1/properties") {
        return jsonResponse(500, { title: "Down", status: 500, code: "HTTP_500", detail: "Down" });
      }
      return jsonResponse(200, ratesBerlin);
    },
    sleep: async () => {},
  });
  assert.equal(report.products.length > 0, true);
  assert.equal(report.workspaceTotal, null);
  assert.ok(report.workspaceError instanceof ApiError);
});

test("an unknown city and a bad slug do not invent a zero", async () => {
  await assert.rejects(
    () =>
      loadReport("no-such-city", "en", {
        fetchImpl: async () => jsonResponse(200, ratesBerlin),
        sleep: async () => {},
      }),
    (error) => error instanceof ApiError && error.code === "UNKNOWN_CITY",
  );
  await assert.rejects(
    () => loadReport("bad/slug", "en", { fetchImpl: async () => jsonResponse(200, {}), sleep: async () => {} }),
    (error) => error instanceof ApiError && error.code === "BAD_CITY",
  );
});

test("loadCities reads the unfiltered rates response", async () => {
  const cities = await loadCities("es", {
    fetchImpl: async (url) => {
      const parsed = new URL(url);
      assert.equal(parsed.searchParams.get("locale"), "es");
      assert.equal(parsed.searchParams.get("city"), null);
      return jsonResponse(200, ratesCities);
    },
    sleep: async () => {},
  });
  assert.equal(cities.some((city) => city.slug === "berlin"), true);
});

test("storage keeps only a valid city slug and defaults to berlin", async () => {
  const saved = {};
  const storage = {
    local: {
      async get(defaults) {
        return { ...defaults, ...saved };
      },
      async set(values) {
        Object.assign(saved, values);
      },
    },
  };
  assert.equal(await readStoredCity(storage), "berlin");
  await writeStoredCity(storage, "madrid");
  assert.deepEqual(saved, { city: "madrid" });
  assert.equal(await readStoredCity(storage), "madrid");
  saved.city = "not a slug";
  assert.equal(await readStoredCity(storage), "berlin");
  await assert.rejects(() => writeStoredCity(storage, "a/b"), (error) => error.code === "BAD_CITY");
});

function load(name) {
  return JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"));
}

function headers(map) {
  return {
    get(name) {
      return map[name.toLowerCase()] ?? null;
    },
  };
}

function jsonResponse(status, body, headerMap = {}, raw = false) {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: headers(headerMap),
    async text() {
      return raw ? body : JSON.stringify(body);
    },
  };
}
