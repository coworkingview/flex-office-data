import { describe, expect, it } from "vitest";

import { ApiError, CoworkingViewClient, retryWaitMs } from "../src/client";
import { readFixture, jsonResponse, scripted, textResponse } from "./fixtures";

const signal = new AbortController().signal;

describe("retryWaitMs", () => {
  it("uses Retry-After, then RateLimit-Reset, then 2 seconds, and caps at 10", () => {
    expect(retryWaitMs({ "Retry-After": "3" })).toBe(3000);
    expect(retryWaitMs({ "Retry-After": "120", "RateLimit-Reset": "5" })).toBe(10000);
    expect(retryWaitMs({ "RateLimit-Reset": "4" })).toBe(4000);
    expect(retryWaitMs({})).toBe(2000);
    expect(retryWaitMs({ "Retry-After": "-3" })).toBe(0);
  });
});

describe("CoworkingViewClient", () => {
  it("requests rates and properties on the public API only", async () => {
    const rates = scripted([jsonResponse(readFixture("market_rates_berlin_usd.json"))]);
    const client = new CoworkingViewClient({ timeoutMs: 1000, get: rates.get, sleep: async () => {} });
    await client.rates("en", "berlin", signal);
    expect(rates.urls).toEqual(["https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin"]);
    expect(rates.headers[0]).toMatchObject({
      Accept: "application/json",
      "User-Agent":
        "lmstudio-plugin-coworkingview-workspace-prices/1.0.0 (+https://github.com/coworkingview/flex-office-data)",
    });

    const cities = scripted([jsonResponse(readFixture("market_rates.json"))]);
    const cityClient = new CoworkingViewClient({ timeoutMs: 1000, get: cities.get, sleep: async () => {} });
    await cityClient.rates("de", null, signal);
    expect(cities.urls[0]).toBe("https://api.coworkingview.com/v1/market/rates?locale=de");

    const spaces = scripted([jsonResponse(readFixture("properties_berlin.json"))]);
    const spaceClient = new CoworkingViewClient({ timeoutMs: 1000, get: spaces.get, sleep: async () => {} });
    await spaceClient.properties("es", "berlin", "flex_desk", signal);
    expect(spaces.urls[0]).toBe(
      "https://api.coworkingview.com/v1/properties?locale=es&city=berlin&page=1&pageSize=10&sortBy=date-desc&pricingOptionType=flex_desk",
    );
  });

  it("retries a 429 once and then a 500 only once", async () => {
    const waits: number[] = [];
    const ok = scripted([
      jsonResponse({}, 429, { "Retry-After": "0" }),
      jsonResponse(readFixture("market_rates.json")),
    ]);
    const client = new CoworkingViewClient({
      timeoutMs: 1000,
      get: ok.get,
      sleep: async ms => {
        waits.push(ms);
      },
    });
    await client.rates("en", null, signal);
    expect(ok.urls).toHaveLength(2);
    expect(waits).toEqual([0]);

    const failing = scripted([
      textResponse("nope", 502),
      jsonResponse(readFixture("error_validation.json"), 500),
    ]);
    const failingClient = new CoworkingViewClient({
      timeoutMs: 1000,
      get: failing.get,
      sleep: async () => {},
    });
    await expect(failingClient.rates("en", "berlin", signal)).rejects.toMatchObject({
      status: 500,
      code: "VALIDATION_FAILED",
    });
    expect(failing.urls).toHaveLength(2);
  });

  it("does not retry a validation error and reports the problem body", async () => {
    const http = scripted([jsonResponse(readFixture("error_validation.json"), 400)]);
    const client = new CoworkingViewClient({ timeoutMs: 1000, get: http.get, sleep: async () => {} });
    await expect(client.rates("en", "berlin", signal)).rejects.toEqual(
      expect.objectContaining({
        name: "ApiError",
        status: 400,
        code: "VALIDATION_FAILED",
        detail: 'currency "VES" has no approximate rate from "EUR" — rates priced in "EUR" cannot be presented in it.',
      }),
    );
    expect(http.urls).toHaveLength(1);
  });

  it("rejects a non-JSON body and a connection failure", async () => {
    const http = scripted([textResponse("<html>", 200)]);
    const client = new CoworkingViewClient({ timeoutMs: 1000, get: http.get, sleep: async () => {} });
    await expect(client.rates("en", null, signal)).rejects.toMatchObject({ code: "BAD_RESPONSE" });

    const broken = new CoworkingViewClient({
      timeoutMs: 1000,
      get: async () => {
        throw new Error("econnrefused");
      },
      sleep: async () => {},
    });
    await expect(broken.rates("en", null, signal)).rejects.toMatchObject({
      status: 0,
      code: "CONNECTION",
    });
  });

  it("turns an aborted timeout into a timeout error", async () => {
    const client = new CoworkingViewClient({
      timeoutMs: 20,
      get: (_url, init) =>
        new Promise((_resolve, reject) => {
          init.signal.addEventListener("abort", () => {
            reject(init.signal.reason);
          });
        }),
      sleep: async () => {},
    });
    await expect(client.rates("en", "berlin", signal)).rejects.toBeInstanceOf(ApiError);
    await expect(client.rates("en", "berlin", signal)).rejects.toMatchObject({ code: "TIMEOUT" });
  });
});
