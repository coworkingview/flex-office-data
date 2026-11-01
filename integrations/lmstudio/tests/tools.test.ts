import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import type { PluginContext, ToolCallContext, ToolsProviderController } from "@lmstudio/sdk";

import { CoworkingViewClient } from "../src/client";
import { main } from "../src/index";
import { ATTRIBUTION_TEXT, HOMEPAGE } from "../src/parse";
import { buildTools, toolsProvider, useClientForTests } from "../src/toolsProvider";
import { jsonResponse, readFixture, scripted } from "./fixtures";

function ctx(): ToolCallContext & { warnings: string[]; statuses: string[] } {
  const warnings: string[] = [];
  const statuses: string[] = [];
  return {
    warnings,
    statuses,
    status: text => {
      statuses.push(text);
    },
    warn: text => {
      warnings.push(text);
    },
    signal: new AbortController().signal,
    callId: 1,
  };
}

function controller(language: "en" | "de" | "es", requestTimeoutSeconds: number): ToolsProviderController {
  return {
    getPluginConfig: () => ({
      get(key: string) {
        if (key === "language") {
          return language;
        }
        if (key === "requestTimeoutSeconds") {
          return requestTimeoutSeconds;
        }
        throw new Error(`unexpected config key ${key}`);
      },
    }),
  } as unknown as ToolsProviderController;
}

afterEach(() => {
  useClientForTests(null);
});

describe("tools", () => {
  it("registers the three read-only tools and the plugin hooks", async () => {
    const http = scripted([jsonResponse(readFixture("market_rates.json"))]);
    let timeoutMs = 0;
    useClientForTests(ms => {
      timeoutMs = ms;
      return new CoworkingViewClient({ timeoutMs: ms, get: http.get, sleep: async () => {} });
    });
    const tools = await toolsProvider(controller("de", 9));
    expect(tools.map(tool => tool.name)).toEqual([
      "get_workspace_prices",
      "search_workspaces",
      "list_cities",
    ]);
    expect(timeoutMs).toBe(9000);

    const hooks: string[] = [];
    await main({
      withConfigSchematics() {
        hooks.push("config");
        return this;
      },
      withToolsProvider() {
        hooks.push("tools");
        return this;
      },
    } as unknown as PluginContext);
    expect(hooks).toEqual(["config", "tools"]);
  });

  it("returns Berlin prices with the CC BY attribution", async () => {
    const http = scripted([jsonResponse(readFixture("market_rates_berlin_usd.json"))]);
    const tools = buildTools(
      "en",
      new CoworkingViewClient({ timeoutMs: 1000, get: http.get, sleep: async () => {} }),
    );
    const prices = tools[0];
    if (prices.type !== "function") {
      throw new Error("expected a function tool");
    }
    const call = ctx();
    const result = await prices.implementation({ city: "berlin", product: "flex_desk" }, call);
    expect(result).toMatchObject({
      city_name: "Berlin",
      attribution_text: ATTRIBUTION_TEXT,
      link: HOMEPAGE,
      prices: [{ median: 233, p25: 216, p75: 317, sample_size: 72 }],
    });
    expect(call.statuses[0]).toContain("berlin");
    expect(http.urls[0]).toContain("locale=en");
  });

  it("uses the configured language and warns on a small sample", async () => {
    const http = scripted([jsonResponse(readFixture("market_rates.json"))]);
    const tools = buildTools(
      "de",
      new CoworkingViewClient({ timeoutMs: 1000, get: http.get, sleep: async () => {} }),
    );
    const prices = tools[0];
    if (prices.type !== "function") {
      throw new Error("expected a function tool");
    }
    const call = ctx();
    const result = await prices.implementation({ city: "abu dhabi" }, call);
    expect(http.urls[0]).toBe("https://api.coworkingview.com/v1/market/rates?locale=de&city=abu-dhabi");
    expect(result).toMatchObject({ attribution_text: ATTRIBUTION_TEXT });
    expect(call.warnings).toEqual(["At least one figure has a sample size under 10."]);
  });

  it("returns an error string for an API failure and does not throw", async () => {
    const http = scripted([jsonResponse(readFixture("error_validation.json"), 400)]);
    const tools = buildTools(
      "en",
      new CoworkingViewClient({ timeoutMs: 1000, get: http.get, sleep: async () => {} }),
    );
    const prices = tools[0];
    if (prices.type !== "function") {
      throw new Error("expected a function tool");
    }
    const result = await prices.implementation({ city: "berlin" }, ctx());
    expect(result).toBe(
      'Error: CoworkingView API 400 VALIDATION_FAILED: currency "VES" has no approximate rate from "EUR" — rates priced in "EUR" cannot be presented in it.',
    );
  });

  it("searches listings and lists cities without calling the network for a bad slug", async () => {
    const spaces = scripted([jsonResponse(readFixture("properties_berlin.json"))]);
    const client = new CoworkingViewClient({ timeoutMs: 1000, get: spaces.get, sleep: async () => {} });
    const tools = buildTools("en", client);
    const search = tools[1];
    const cities = tools[2];
    if (search.type !== "function" || cities.type !== "function") {
      throw new Error("expected function tools");
    }
    const found = await search.implementation({ city: "berlin", language: "es" }, ctx());
    expect(found).toMatchObject({
      total: 110,
      attribution_text: ATTRIBUTION_TEXT,
      link: HOMEPAGE,
    });
    expect(JSON.stringify(found)).not.toContain("example.com");
    expect(spaces.urls[0]).toContain("locale=es");
    expect(spaces.urls[0]).not.toContain("pricingOptionType");

    const bad = await search.implementation({ city: "!!" }, ctx());
    expect(bad).toMatch(/Error: city must be a CoworkingView city slug/);
    expect(spaces.urls).toHaveLength(1);

    const index = scripted([jsonResponse(readFixture("market_rates.json"))]);
    const cityClient = new CoworkingViewClient({ timeoutMs: 1000, get: index.get, sleep: async () => {} });
    const listed = buildTools("en", cityClient)[2];
    if (listed.type !== "function") {
      throw new Error("expected a function tool");
    }
    const rows = await listed.implementation({}, ctx());
    expect(rows).toMatchObject({ attribution_text: ATTRIBUTION_TEXT, link: HOMEPAGE });
    expect(JSON.stringify(rows)).not.toContain("example-town");
    expect(index.urls[0]).toBe("https://api.coworkingview.com/v1/market/rates?locale=en");
  });

  it("keeps the Hub README and the manifest", () => {
    const readme = readFileSync(join(process.cwd(), "README.md"), "utf8");
    expect(readme).toContain("https://coworkingview.com");
    expect(readme).toContain("https://coworkingview.com/en/api");
    expect(readme).toContain(ATTRIBUTION_TEXT);
    expect(readme).toContain("CC BY 4.0");
    expect(readme).toContain("MIT");
    expect(readme).toContain("AI assistance");
    expect(readme).toContain("Element Labs");
    expect(readme).toContain("LM Studio");
    expect(readme).toMatch(/city, the optional product, and the language/i);

    const publish = readFileSync(join(process.cwd(), "PUBLISH.md"), "utf8");
    expect(publish).toContain("lms login");
    expect(publish).toContain("lms push");
    expect(publish).toContain("--with-pre-authenticated-keys");

    const manifest = JSON.parse(readFileSync(join(process.cwd(), "manifest.json"), "utf8")) as {
      type: string;
      runner: string;
      owner: string;
      name: string;
      revision: number;
    };
    expect(manifest).toEqual({
      type: "plugin",
      runner: "node",
      owner: "coworkingview",
      name: "coworkingview-workspace-prices",
      revision: 1,
    });
  });
});
