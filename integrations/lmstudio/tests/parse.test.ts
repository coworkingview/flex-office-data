import { describe, expect, it } from "vitest";

import { ATTRIBUTION_TEXT, HOMEPAGE, parseCities, parsePrices, parseWorkspaces } from "../src/parse";
import { readFixture } from "./fixtures";

const attribution =
  "Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), as of October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Aggregated figures only; no endorsement by CoworkingView or any operator is implied.";

describe("parsePrices", () => {
  const berlin = readFixture("market_rates_berlin_usd.json");

  it("reads median, percentiles, and sample size for Berlin", () => {
    const parsed = parsePrices(berlin, "berlin", null);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.snapshot.city_name).toBe("Berlin");
    expect(parsed.snapshot.country_code).toBe("DE");
    expect(parsed.snapshot.currency).toBe("USD");
    expect(parsed.snapshot.prices.map(row => row.product)).toEqual([
      "flex_desk",
      "fix_desk",
      "private_office",
      "day_pass",
      "meeting_room",
    ]);
    expect(parsed.snapshot.prices[0]).toMatchObject({
      product: "flex_desk",
      unit: "month",
      median: 233,
      currency: "USD",
      p25: 216,
      p75: 317,
      sample_size: 72,
      low_confidence: false,
    });
    expect(parsed.snapshot.prices[3]).toMatchObject({
      product: "day_pass",
      unit: "day",
      median: 38,
      p25: null,
      p75: null,
      sample_size: 59,
    });
    expect(parsed.snapshot.prices[4]).toMatchObject({
      product: "meeting_room",
      unit: "hour",
      median: 35,
      sample_size: 79,
    });
    expect(parsed.snapshot.attribution).toBe(attribution);
    expect(parsed.snapshot.license).toBe("CC-BY-4.0");
    expect(parsed.snapshot.license_url).toBe("https://creativecommons.org/licenses/by/4.0/");
    expect(parsed.snapshot.attribution_text).toBe(ATTRIBUTION_TEXT);
    expect(parsed.snapshot.link).toBe(HOMEPAGE);
    expect(parsed.snapshot.as_of).toBe("2026-10-27T21:06:48.313Z");
  });

  it("keeps one product when asked", () => {
    const parsed = parsePrices(berlin, "Berlin", "private_office");
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.snapshot.prices).toHaveLength(1);
    expect(parsed.snapshot.prices[0].median).toBe(522);
    expect(parsed.snapshot.prices[0].p25).toBe(434);
    expect(parsed.snapshot.prices[0].p75).toBe(598);
    expect(parsed.snapshot.prices[0].sample_size).toBe(59);
  });

  it("falls back to byType and leaves percentiles null", () => {
    const copy = structuredClone(berlin) as { data: { cities: Array<{ figures?: unknown }> } };
    delete copy.data.cities[0].figures;
    const parsed = parsePrices(copy, "berlin", "flex_desk");
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.snapshot.prices[0]).toMatchObject({
      median: 233,
      p25: null,
      p75: null,
      sample_size: 72,
      unit: "month",
    });
  });

  it("marks a small sample as low confidence and does not invent a zero", () => {
    const parsed = parsePrices(readFixture("market_rates.json"), "abu-dhabi", "flex_desk");
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.snapshot.prices[0]).toMatchObject({
      median: 1400,
      currency: "AED",
      p25: 1400,
      p75: 1800,
      sample_size: 3,
      low_confidence: true,
    });
  });

  it("refuses an unpublished city and an unknown product", () => {
    const index = readFixture("market_rates.json");
    expect(parsePrices(index, "example-town", null)).toEqual({
      ok: false,
      message: 'Error: "example-town" is not a published CoworkingView city. Call list_cities for published slugs.',
    });
    const missing = parsePrices(berlin, "berlin", "event_space");
    expect(missing.ok).toBe(false);
    if (missing.ok) {
      return;
    }
    expect(missing.message).toContain("event_space");
    expect(missing.message).toContain("flex_desk");
    expect(missing.message).not.toContain("0");
  });
});

describe("parseCities", () => {
  it("lists published cities and skips unpublished", () => {
    const body = readFixture("market_rates.json") as {
      data: { cities: Array<{ city: { slug: string } }> };
    };
    const parsed = parseCities(body);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    const slugs = body.data.cities.map(city => city.city.slug).sort();
    expect(parsed.list.cities.map(city => city.slug)).toEqual(slugs);
    expect(parsed.list.cities.map(city => city.slug)).not.toContain("example-town");
    const berlin = parsed.list.cities.find(city => city.slug === "berlin");
    expect(berlin?.name).toBe("Berlin");
    expect(berlin?.country_code).toBe("DE");
    expect(parsed.list.attribution_text).toBe(ATTRIBUTION_TEXT);
    expect(parsed.list.link).toBe(HOMEPAGE);
  });
});

describe("parseWorkspaces", () => {
  it("keeps catalogue fields and drops descriptions and images", () => {
    const parsed = parseWorkspaces(readFixture("properties_berlin.json"), "en");
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.search.total).toBe(110);
    expect(parsed.search.workspaces).toHaveLength(3);
    expect(parsed.search.workspaces[0]).toEqual({
      slug: "sankt-oberholz-rosenthaler-berlin",
      title: "St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße",
      city_slug: "berlin",
      zone_slug: "mitte",
      operator_slug: "sankt-oberholz",
      operator_name: "St. Oberholz",
      country_code: "DE",
      lat: 52.5294539,
      lng: 13.4018374,
      featured: true,
      market_verdict: "around",
      market_median: 214,
      market_currency: "EUR",
      market_sample_size: 72,
      url: "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
      updated_at: "2026-10-19T16:27:57.522Z",
    });
    const encoded = JSON.stringify(parsed.search);
    expect(encoded).not.toContain("example.com");
    expect(encoded).not.toContain("Example description");
    expect(encoded).not.toContain(".webp");
    expect(parsed.search.citation).toBe(
      "Source: CoworkingView — Coworking spaces in Berlin, https://coworkingview.com/en/coworking/berlin.",
    );
    expect(parsed.search.notice).toContain("Systematic extraction");
    expect(parsed.search.attribution_text).toBe(ATTRIBUTION_TEXT);
    expect(parsed.search.link).toBe(HOMEPAGE);
  });

  it("uses the locale in the listing path", () => {
    const parsed = parseWorkspaces(readFixture("properties_berlin.json"), "de");
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.search.workspaces[0].url).toBe(
      "https://coworkingview.com/de/buero/sankt-oberholz-rosenthaler-berlin",
    );
    const spanish = parseWorkspaces(readFixture("properties_berlin.json"), "es");
    expect(spanish.ok).toBe(true);
    if (!spanish.ok) {
      return;
    }
    expect(spanish.search.workspaces[0].url).toContain("/es/oficina/");
  });

  it("reads an empty page", () => {
    const parsed = parseWorkspaces(readFixture("properties_empty.json"), "en");
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    expect(parsed.search.workspaces).toEqual([]);
    expect(parsed.search.total).toBe(0);
    expect(parsed.search.attribution_text).toBe(ATTRIBUTION_TEXT);
  });
});
