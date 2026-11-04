import { errorText, priceLine, productLabel, spreadLine, translate } from './format';

const HOME = 'https://coworkingview.com';
const INDEX = 'https://coworkingview.com/en/tools/price-index';
const LICENSE = 'https://creativecommons.org/licenses/by/4.0/';

function el(tag, className, text) {
  const node = document.createElement(tag);
  node.className = className;
  if (text != null) {
    node.textContent = text;
  }
  return node;
}

function link(href, className, text) {
  const node = document.createElement('a');
  node.href = href;
  node.rel = 'noopener noreferrer';
  node.className = className;
  node.textContent = text;
  return node;
}

function credit() {
  const line = el('p', 'CoworkingViewCard-credit');
  line.appendChild(link(HOME, '', 'CoworkingView'));
  line.appendChild(document.createTextNode(' · '));
  line.appendChild(link(LICENSE, '', 'CC BY 4.0'));
  return line;
}

export function fillElement(root, payload) {
  root.textContent = '';
  root.setAttribute('data-ready', payload && payload.ok ? '1' : '0');

  if (!payload || payload.ok !== true) {
    root.appendChild(el('p', 'CoworkingViewCard-error', errorText(payload && payload.code)));
    const line = el('p', 'CoworkingViewCard-credit');
    line.appendChild(link(HOME, '', 'CoworkingView'));
    root.appendChild(line);
    return;
  }

  const city = el('p', 'CoworkingViewCard-city');
  city.appendChild(link(INDEX, '', payload.cityName || payload.citySlug || ''));
  root.appendChild(city);

  if (payload.asOf) {
    const date = String(payload.asOf).slice(0, 10);
    root.appendChild(el('p', 'CoworkingViewCard-asof', translate('as_of', { date })));
  }

  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  if (rows.length === 0) {
    root.appendChild(el('p', 'CoworkingViewCard-empty', translate('empty')));
  } else {
    const list = el('ul', 'CoworkingViewCard-rows');
    rows.forEach((row) => {
      const item = el('li', 'CoworkingViewCard-row');
      item.appendChild(el('span', 'CoworkingViewCard-product', productLabel(row.product)));
      item.appendChild(el('span', 'CoworkingViewCard-price', priceLine(row)));
      const spread = spreadLine(row);
      if (spread) {
        item.appendChild(el('span', 'CoworkingViewCard-spread', spread));
      }
      if (typeof row.sampleSize === 'number') {
        item.appendChild(el('span', 'CoworkingViewCard-sample', translate('sample', { count: String(row.sampleSize) })));
      }
      if (row.lowConfidence === true) {
        item.appendChild(el('span', 'CoworkingViewCard-low', translate('low_confidence')));
      }
      list.appendChild(item);
    });
    root.appendChild(list);
  }

  if (payload.attribution) {
    root.appendChild(el('p', 'CoworkingViewCard-attribution', payload.attribution));
  }
  root.appendChild(credit());
}
