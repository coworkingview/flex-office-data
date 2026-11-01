import { localizeDocument, translatorFromMessages } from "../../addon/lib/i18n.js";
import { parseCities, parseCityRates, parseWorkspaceCount } from "../../addon/lib/parse.js";
import { fillCitySelect, renderReport } from "../../addon/lib/render.js";

const messages = await fetch("/addon/_locales/en/messages.json").then((response) => response.json());
const translate = translatorFromMessages(messages);
localizeDocument(document, translate);
document.documentElement.lang = "en";

const rates = await fetch("/tests/fixtures/rates-berlin.json").then((response) => response.json());
const citiesBody = await fetch("/tests/fixtures/rates-cities.json").then((response) => response.json());
const properties = await fetch("/tests/fixtures/properties-berlin.json").then((response) => response.json());
const report = parseCityRates(rates, "berlin");
const count = parseWorkspaceCount(properties);
fillCitySelect(document.getElementById("city"), parseCities(citiesBody), "berlin");
renderReport(
  document,
  {
    ...report,
    workspaceTotal: count.total,
    citation: count.citation,
    citationUrl: count.citationUrl,
    workspaceError: null,
  },
  translate,
  "en",
);
