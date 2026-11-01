import { text, tool, type Tool, type ToolsProviderController } from "@lmstudio/sdk";
import { z } from "zod";
import { CoworkingViewClient, errorMessage } from "./client";
import { configSchematics } from "./config";
import {
  ATTRIBUTION_TEXT,
  HOMEPAGE,
  InputError,
  LOCALES,
  PAGE_SIZE,
  PRODUCTS,
  type Locale,
  normalizeCity,
  normalizeLocale,
  normalizeProduct,
  parseCities,
  parsePrices,
  parseWorkspaces,
} from "./parse";

// See details about defining tools in the documentation:
// https://lmstudio.ai/docs/typescript/plugins/tools-provider

type ClientFactory = (timeoutMs: number) => CoworkingViewClient;

let clientFactory: ClientFactory = timeoutMs => new CoworkingViewClient({ timeoutMs });

/** Tests replace the HTTPS transport. Production always uses the public API. */
export function useClientForTests(factory: ClientFactory | null): void {
  clientFactory = factory ?? (timeoutMs => new CoworkingViewClient({ timeoutMs }));
}

export function buildTools(language: Locale, client: CoworkingViewClient): Tool[] {
  const tools: Tool[] = [];

  const getWorkspacePrices = tool({
    name: "get_workspace_prices",
    description: text`
      Look up indicative flexible-workspace prices for one published city from the CoworkingView
      Price Index (GET /v1/market/rates on https://api.coworkingview.com).

      Returns, for each product, the median, the 25th and 75th percentile when the API published
      them, and the sample size. A missing percentile is null, not zero. A sample size under 10 is
      low confidence. Prices are aggregates, not a quote for a particular space.

      \`city\` is a slug such as berlin or abu-dhabi. Call list_cities when you do not know the slug.
      \`product\` is optional. Omit it to return every product the city publishes.
      \`language\` is optional and must be en, de, or es. It is sent as the locale query parameter.

      Always show the user the attribution_text and the link ${HOMEPAGE}. The Price Index is
      CC BY 4.0. Keep the attribution string the API returned as well.
    `,
    parameters: {
      city: z.string().describe("City slug, for example berlin or madrid. Not a free-text address."),
      product: z
        .enum(PRODUCTS)
        .optional()
        .describe("One product. Omit to return every product the city publishes."),
      language: z.enum(LOCALES).optional().describe("Locale sent to the API: en, de, or es."),
    },
    implementation: async ({ city, product, language: languageArg }, { status, warn, signal }) => {
      try {
        const slug = normalizeCity(city);
        const locale = normalizeLocale(languageArg, language);
        const selected = normalizeProduct(product);
        status(`Fetching CoworkingView prices for ${slug}`);
        const body = await client.rates(locale, slug, signal);
        const parsed = parsePrices(body, slug, selected);
        if (!parsed.ok) {
          return parsed.message;
        }
        if (parsed.snapshot.prices.some(row => row.low_confidence)) {
          warn("At least one figure has a sample size under 10.");
        }
        return parsed.snapshot;
      } catch (error) {
        return fail(error, signal);
      }
    },
  });
  tools.push(getWorkspacePrices);

  const searchWorkspaces = tool({
    name: "search_workspaces",
    description: text`
      Search the public CoworkingView catalogue for listings in one city
      (GET /v1/properties on https://api.coworkingview.com).

      Returns at most ${PAGE_SIZE} listings from the first page, each with a link on
      ${HOMEPAGE}. Photos, logos, and descriptions are not returned. This is not a way to
      download the catalogue. The catalogue notice in the result applies: you may link to
      listing pages, and systematic extraction is not permitted.

      \`city\` is a slug from list_cities. \`product\` is optional and filters by pricingOptionType.
      \`language\` is optional (en, de, or es) and chooses the listing URL language.

      Always show attribution_text ("${ATTRIBUTION_TEXT}") and the link.
    `,
    parameters: {
      city: z.string().describe("City slug, for example berlin."),
      product: z
        .enum(PRODUCTS)
        .optional()
        .describe("Optional product filter, sent as pricingOptionType."),
      language: z.enum(LOCALES).optional().describe("Locale sent to the API: en, de, or es."),
    },
    implementation: async ({ city, product, language: languageArg }, { status, signal }) => {
      try {
        const slug = normalizeCity(city);
        const locale = normalizeLocale(languageArg, language);
        const selected = normalizeProduct(product);
        status(`Searching CoworkingView listings in ${slug}`);
        const body = await client.properties(locale, slug, selected, signal);
        const parsed = parseWorkspaces(body, locale);
        if (!parsed.ok) {
          return parsed.message;
        }
        return parsed.search;
      } catch (error) {
        return fail(error, signal);
      }
    },
  });
  tools.push(searchWorkspaces);

  const listCities = tool({
    name: "list_cities",
    description: text`
      List cities with a published CoworkingView Price Index
      (GET /v1/market/rates on https://api.coworkingview.com, with no city parameter).

      Unpublished cities are omitted. Use the slug as the city argument of get_workspace_prices
      and search_workspaces. \`language\` is optional (en, de, or es).

      Always show attribution_text ("${ATTRIBUTION_TEXT}") and the link ${HOMEPAGE}.
      The index is CC BY 4.0.
    `,
    parameters: {
      language: z.enum(LOCALES).optional().describe("Locale sent to the API: en, de, or es."),
    },
    implementation: async ({ language: languageArg }, { status, signal }) => {
      try {
        const locale = normalizeLocale(languageArg, language);
        status("Fetching published CoworkingView cities");
        const body = await client.rates(locale, null, signal);
        const parsed = parseCities(body);
        if (!parsed.ok) {
          return parsed.message;
        }
        return parsed.list;
      } catch (error) {
        return fail(error, signal);
      }
    },
  });
  tools.push(listCities);

  return tools;
}

export async function toolsProvider(ctl: ToolsProviderController): Promise<Tool[]> {
  const config = ctl.getPluginConfig(configSchematics);
  const language = normalizeLocale(config.get("language"), "en");
  const timeoutMs = timeoutFromConfig(config.get("requestTimeoutSeconds"));
  return buildTools(language, clientFactory(timeoutMs));
}

function timeoutFromConfig(seconds: number): number {
  if (!Number.isFinite(seconds)) {
    return 20_000;
  }
  const clamped = Math.min(120, Math.max(1, seconds));
  return Math.round(clamped * 1000);
}

function fail(error: unknown, signal: AbortSignal): string {
  if (signal.aborted) {
    throw error;
  }
  if (error instanceof InputError) {
    return `Error: ${error.message}`;
  }
  return errorMessage(error);
}
