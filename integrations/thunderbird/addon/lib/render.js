/**
 * Draws the price table. Every string the user reads is either an i18n
 * message or a value copied from the API (city name, attribution, amounts).
 */

export function showStatus(element, text) {
  element.textContent = text || "";
  element.hidden = !text;
}

export function fillCitySelect(select, cities, selected) {
  const doc = select.ownerDocument;
  select.replaceChildren();
  const known = new Set(cities.map((city) => city.slug));
  const items = cities.slice();
  if (selected && !known.has(selected)) {
    items.unshift({ slug: selected, name: selected });
  }
  for (const city of items) {
    const option = doc.createElement("option");
    option.value = city.slug;
    option.textContent = city.name === city.slug ? city.slug : `${city.name} (${city.slug})`;
    if (city.slug === selected) {
      option.selected = true;
    }
    select.append(option);
  }
}

export function renderReport(root, report, translate, locale) {
  const doc = root.ownerDocument || root;
  const results = root.querySelector("#results");
  const rows = root.querySelector("#rows");
  const summary = root.querySelector("#summary");
  const workspaces = root.querySelector("#workspaces");
  const asof = root.querySelector("#asof");
  const attribution = root.querySelector("#attribution");
  const license = root.querySelector("#license");
  const citation = root.querySelector("#citation");

  rows.replaceChildren();
  license.replaceChildren();
  citation.replaceChildren();

  if (!report) {
    results.hidden = true;
    summary.textContent = "";
    workspaces.textContent = "";
    asof.textContent = "";
    attribution.textContent = "";
    return;
  }

  results.hidden = false;
  summary.textContent = report.currency
    ? `${report.cityName} · ${report.currency}`
    : report.cityName;

  for (const product of report.products) {
    rows.append(renderRow(doc, product, report.currency, translate, locale));
  }

  if (report.workspaceError) {
    workspaces.textContent = translate("workspaceUnavailable");
  } else if (typeof report.workspaceTotal === "number") {
    workspaces.textContent = translate("workspaceCount", String(report.workspaceTotal));
  } else {
    workspaces.textContent = "";
  }

  if (report.asOf) {
    asof.textContent = translate("asOf", [formatAsOf(report.asOf, locale), report.asOf]);
  } else {
    asof.textContent = "";
  }

  attribution.textContent = report.attribution || translate("attributionMissing");

  if (report.licenseUrl) {
    const link = doc.createElement("a");
    link.href = report.licenseUrl;
    link.textContent = translate("licenseLink");
    license.append(link);
  }

  if (report.citation) {
    citation.append(doc.createTextNode(report.citation));
  }
  if (report.citationUrl) {
    if (report.citation) {
      citation.append(doc.createTextNode(" "));
    }
    const link = doc.createElement("a");
    link.href = report.citationUrl;
    link.textContent = translate("cityPage");
    citation.append(link);
  }
}

function renderRow(doc, product, cityCurrency, translate, locale) {
  const row = doc.createElement("tr");
  row.append(productCell(doc, product, translate));
  row.append(moneyCell(doc, product.median, cityCurrency, translate, locale));
  row.append(moneyCell(doc, product.p25, cityCurrency, translate, locale));
  row.append(moneyCell(doc, product.p75, cityCurrency, translate, locale));
  row.append(sampleCell(doc, product, translate));
  return row;
}

function productCell(doc, product, translate) {
  const cell = doc.createElement("td");
  const name = doc.createElement("span");
  name.className = "product-name";
  name.textContent = productLabel(translate, product.product);
  cell.append(name);
  if (product.unit) {
    const unit = doc.createElement("span");
    unit.className = "product-unit";
    const translated = translate(`unit_${product.unit}`);
    unit.textContent = translated || product.unit;
    cell.append(unit);
  }
  return cell;
}

function moneyCell(doc, money, cityCurrency, translate, locale) {
  const cell = doc.createElement("td");
  cell.className = "num";
  if (!money) {
    cell.textContent = translate("notPublished");
    return cell;
  }
  cell.textContent = formatMoney(money.amount, money.currency || cityCurrency, locale);
  return cell;
}

function sampleCell(doc, product, translate) {
  const cell = doc.createElement("td");
  cell.className = "num";
  if (product.sampleSize == null) {
    cell.textContent = translate("notPublished");
    return cell;
  }
  cell.textContent = String(product.sampleSize);
  if (product.lowConfidence) {
    const note = doc.createElement("span");
    note.className = "low-confidence";
    note.textContent = translate("lowConfidence");
    cell.append(doc.createTextNode(" "));
    cell.append(note);
  }
  return cell;
}

function productLabel(translate, product) {
  const translated = translate(`product_${product}`);
  return translated || product;
}

export function formatMoney(amount, currency, locale) {
  if (typeof amount !== "number") {
    return "";
  }
  if (currency) {
    try {
      return new Intl.NumberFormat(locale, {
        style: "currency",
        currency,
        maximumFractionDigits: Number.isInteger(amount) ? 0 : 2,
      }).format(amount);
    } catch {
      return `${amount} ${currency}`;
    }
  }
  return String(amount);
}

function formatAsOf(raw, locale) {
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    return raw;
  }
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}
