/**
 * Popup for the message display and compose buttons.
 * The displayed message is not read. The user picks the city.
 */

import { ApiError } from "../lib/errors.js";
import { localizeDocument } from "../lib/i18n.js";
import { loadCities, loadReport } from "../lib/http.js";
import { fillCitySelect, renderReport, showStatus } from "../lib/render.js";
import { readStoredCity, writeStoredCity } from "../lib/storage.js";
import { uiLocale } from "../lib/parse.js";

const browserApi = globalThis.browser;

function translate(key, substitutions) {
  return browserApi.i18n.getMessage(key, substitutions) || "";
}

function errorText(error) {
  if (error instanceof ApiError) {
    if (error.code === "UNKNOWN_CITY") {
      return translate("errorUnknownCity");
    }
    if (error.code === "BAD_CITY") {
      return translate("errorBadCity");
    }
    if (error.code === "BAD_RESPONSE") {
      return translate("errorBadResponse");
    }
    if (error.status === 429) {
      return translate("errorRateLimit");
    }
    if (error.message) {
      return translate("errorApi", error.message);
    }
  }
  return translate("errorNetwork");
}

localizeDocument(document, translate);

const locale = uiLocale(browserApi.i18n.getUILanguage());
document.documentElement.lang = locale;

const form = document.getElementById("city-form");
const select = document.getElementById("city");
const status = document.getElementById("status");
let generation = 0;

document.getElementById("open-options").addEventListener("click", () => {
  browserApi.runtime.openOptionsPage();
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  void refresh(select.value, true);
});

select.addEventListener("change", () => {
  void refresh(select.value, true);
});

async function refresh(city, persist) {
  const ticket = ++generation;
  showStatus(status, translate("loading"));
  try {
    const report = await loadReport(city, locale);
    if (ticket !== generation) {
      return;
    }
    renderReport(document, report, translate, locale);
    if (persist) {
      await writeStoredCity(browserApi.storage, city);
    }
    if (ticket !== generation) {
      return;
    }
    showStatus(status, "");
  } catch (error) {
    if (ticket !== generation) {
      return;
    }
    renderReport(document, null, translate, locale);
    showStatus(status, errorText(error));
  }
}

async function init() {
  const city = await readStoredCity(browserApi.storage);
  showStatus(status, translate("loading"));
  try {
    const cities = await loadCities(locale);
    fillCitySelect(select, cities, city);
  } catch (error) {
    fillCitySelect(select, [], city);
    showStatus(status, errorText(error));
  }
  await refresh(select.value || city, false);
}

void init();
