import app from 'flarum/forum/app';

const PREFIX = 'coworkingview-flarum-coworkingview.forum';

export function plain(value) {
  if (value == null) {
    return '';
  }
  if (typeof value === 'string' || typeof value === 'number') {
    return String(value);
  }
  if (Array.isArray(value)) {
    return value.map(plain).join('');
  }
  if (typeof value === 'object') {
    if (typeof value.text === 'string') {
      return value.text;
    }
    if (value.children != null) {
      return plain(value.children);
    }
  }
  return '';
}

export function translate(key, params) {
  if (!app.translator) {
    return key;
  }
  return plain(app.translator.trans(`${PREFIX}.${key}`, params || {}));
}

export function formatAmount(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return '';
  }
  if (Object.is(value, -0)) {
    return '0';
  }
  const text = String(value);
  if (!/[eE]/.test(text)) {
    return text;
  }
  return value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

export function productLabel(code) {
  const key = `products.${code}`;
  const text = translate(key);
  if (!text || text === `${PREFIX}.${key}` || text === key) {
    return String(code || '').replace(/_/g, ' ');
  }
  return text;
}

export function unitLabel(unit) {
  if (!unit) {
    return '';
  }
  const key = `units.${unit}`;
  const text = translate(key);
  if (!text || text === `${PREFIX}.${key}` || text === key) {
    return unit;
  }
  return text;
}

export function priceLine(row) {
  const amount = formatAmount(row.median);
  if (amount === '') {
    return '';
  }
  let text = row.currency ? `${amount} ${row.currency}` : amount;
  const unit = unitLabel(row.unit);
  if (unit) {
    text += ` / ${unit}`;
  }
  return text;
}

export function spreadLine(row) {
  if (typeof row.p25 !== 'number' || typeof row.p75 !== 'number') {
    return '';
  }
  return `${formatAmount(row.p25)}–${formatAmount(row.p75)}`;
}

export function errorText(code) {
  const key = `errors.${code || 'unavailable'}`;
  const text = translate(key);
  if (!text || text === `${PREFIX}.${key}` || text === key) {
    return translate('errors.unavailable');
  }
  return text;
}
