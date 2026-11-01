/**
 * Options page. Saves the default city slug and nothing else.
 */

import { ApiError } from "../lib/errors.js";
import { localizeDocument } from "../lib/i18n.js";
import { loadCities } from "../lib/http.js";
import { fillCitySelect, showStatus } from "../lib/render.js";
import { readStoredCity, writeStoredCity } from "../lib/storage.js";
import { uiLocale } from "../lib/parse.js";

const browserApi = globalThis.browser;

function translate(key, substitutions) {
  return browserApi.i18n.getMessage(key, substitutions) || "";
}

async function save() {
  try {
    await writeStoredCity(browserApi.storage, input.value.trim());
    showStatus(saved, translate("optionsSaved"));
  } catch (error) {
    const text =
      error instanceof ApiError && error.code === "BAD_CITY"
        ? translate("errorBadCity")
        : translate("errorNetwork");
    showStatus(saved, text);
  }
}

async function init() {
  const city = await readStoredCity(browserApi.storage);
  input.value = city;
  try {
    const cities = await loadCities(locale);
    fillCitySelect(select, cities, city);
  } catch {
    fillCitySelect(select, [], city);
    showStatus(saved, translate("citiesUnavailable"));
  }
}

localizeDocument(document, translate);

const locale = uiLocale(browserApi.i18n.getUILanguage());
document.documentElement.lang = locale;

const form = document.getElementById("options-form");
const input = document.getElementById("city");
const select = document.getElementById("cities");
const saved = document.getElementById("saved");

select.addEventListener("change", () => {
  if (select.value) {
    input.value = select.value;
  }
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  void save();
});

void init();
