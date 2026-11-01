import { localizeDocument, translatorFromMessages } from "../../addon/lib/i18n.js";
import { parseCities } from "../../addon/lib/parse.js";
import { fillCitySelect } from "../../addon/lib/render.js";

const messages = await fetch("/addon/_locales/en/messages.json").then((response) => response.json());
const translate = translatorFromMessages(messages);
localizeDocument(document, translate);
document.documentElement.lang = "en";

const citiesBody = await fetch("/tests/fixtures/rates-cities.json").then((response) => response.json());
const input = document.getElementById("city");
const select = document.getElementById("cities");
input.value = "berlin";
fillCitySelect(select, parseCities(citiesBody), "berlin");
select.addEventListener("change", () => {
  input.value = select.value;
});
