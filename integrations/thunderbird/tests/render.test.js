import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { JSDOM } from "jsdom";

import { localizeDocument, translatorFromMessages } from "../addon/lib/i18n.js";
import { loadReport } from "../addon/lib/http.js";
import { fillCitySelect, formatMoney, renderReport } from "../addon/lib/render.js";

globalThis.fetch = () => {
  throw new Error("network disabled in tests");
};

const messages = JSON.parse(
  readFileSync(new URL("../addon/_locales/en/messages.json", import.meta.url), "utf8"),
);
const translate = translatorFromMessages(messages);
const ratesBerlin = JSON.parse(
  readFileSync(new URL("./fixtures/rates-berlin.json", import.meta.url), "utf8"),
);
const propertiesBerlin = JSON.parse(
  readFileSync(new URL("./fixtures/properties-berlin.json", import.meta.url), "utf8"),
);

test("the popup shows prices, the verbatim attribution, and not the listing", async () => {
  const report = await loadReport("berlin", "en", {
    fetchImpl: async (url) => {
      const path = new URL(url).pathname;
      const body = path === "/v1/properties" ? propertiesBerlin : ratesBerlin;
      return {
        status: 200,
        ok: true,
        headers: { get() { return null; } },
        async text() {
          return JSON.stringify(body);
        },
      };
    },
    sleep: async () => {},
  });

  const dom = new JSDOM(readFileSync(new URL("../addon/popup/popup.html", import.meta.url), "utf8"));
  const { document } = dom.window;
  localizeDocument(document, translate);
  assert.equal(document.querySelector("h1").textContent, "CoworkingView prices");
  assert.equal(document.querySelector("button[type=submit]").textContent, "Refresh");

  renderReport(document, report, translate, "en");
  const text = document.body.textContent;
  assert.equal(text.includes("Berlin"), true);
  assert.equal(text.includes("Flex desk"), true);
  assert.equal(text.includes("per month"), true);
  assert.equal(text.includes("Day pass"), true);
  assert.equal(text.includes("per day"), true);
  assert.equal(text.includes("Meeting room"), true);
  assert.equal(text.includes("per hour"), true);
  assert.equal(text.includes(ratesBerlin.data.attribution), true);
  assert.equal(text.includes("CC BY 4.0"), true);
  assert.equal(text.includes("110 workspace listings in this city"), true);
  assert.equal(text.includes(propertiesBerlin.meta.citation.text), true);
  assert.equal(text.includes("St. Oberholz"), false);
  assert.equal(text.includes("example.com"), false);
  assert.equal(text.includes("betahaus"), false);
  assert.equal(document.querySelector("#license a").getAttribute("href"), ratesBerlin.data.licenseUrl);
  assert.equal(document.querySelector("#results").hidden, false);

  const amounts = [...document.querySelectorAll("td.num")].map((cell) => cell.textContent);
  assert.equal(amounts.some((value) => value.includes("233")), true);
  assert.equal(amounts.includes("0"), false);
});

test("a missing percentile is not rendered as zero", () => {
  const dom = new JSDOM(`<section id="results"><p id="summary"></p><table><tbody id="rows"></tbody></table><p id="workspaces"></p><p id="asof"></p><p id="attribution"></p><p id="license"></p><p id="citation"></p></section>`);
  renderReport(
    dom.window.document,
    {
      cityName: "Berlin",
      currency: "EUR",
      products: [
        {
          product: "day_pass",
          unit: "day",
          median: { amount: 35, currency: "EUR" },
          p25: null,
          p75: null,
          sampleSize: 4,
          lowConfidence: true,
        },
      ],
      attribution: "Source: keep this exact.",
      licenseUrl: null,
      asOf: "2026-10-30T13:21:31.959Z",
      workspaceTotal: 0,
      citation: null,
      citationUrl: null,
      workspaceError: null,
    },
    translate,
    "en",
  );
  const cells = [...dom.window.document.querySelectorAll("td")].map((cell) => cell.textContent);
  assert.equal(cells[2].includes("—"), true);
  assert.equal(cells[2].includes("0"), false);
  assert.equal(cells[4].includes("fewer than 10 observations"), true);
  assert.equal(dom.window.document.querySelector("#workspaces").textContent, "0 workspace listings in this city");
  assert.equal(dom.window.document.querySelector("#attribution").textContent, "Source: keep this exact.");
});

test("clearing the report hides the table", () => {
  const dom = new JSDOM(`<section id="results"><p id="summary"></p><table><tbody id="rows"></tbody></table><p id="workspaces"></p><p id="asof"></p><p id="attribution"></p><p id="license"></p><p id="citation"></p></section>`);
  renderReport(dom.window.document, null, translate, "en");
  assert.equal(dom.window.document.querySelector("#results").hidden, true);
});

test("city select labels come from the API name and slug", () => {
  const dom = new JSDOM(`<select id="cities"></select>`);
  const select = dom.window.document.getElementById("cities");
  fillCitySelect(
    select,
    [
      { slug: "berlin", name: "Berlin" },
      { slug: "madrid", name: "Madrid" },
    ],
    "madrid",
  );
  assert.equal(select.value, "madrid");
  assert.equal(select.options[0].textContent, "Berlin (berlin)");
  assert.equal(formatMoney(214, "EUR", "en"), new Intl.NumberFormat("en", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 0,
  }).format(214));
});

test("placeholder substitution matches the messages file", () => {
  assert.equal(translate("workspaceCount", "143"), "143 workspace listings in this city");
  assert.equal(translate("errorApi", "Validation failed"), "The API returned an error: Validation failed");
  assert.equal(translate("missingKey"), "");
});
