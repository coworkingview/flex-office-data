import app from 'flarum/forum/app';

const pending = new Map();

export function loadRates(city, product, locale) {
  const key = [city, product || '', locale || ''].join('\n');
  if (!pending.has(key)) {
    const params = { city, locale: locale || 'en' };
    if (product && product !== 'all') {
      params.product = product;
    }
    const request = app
      .request({
        method: 'GET',
        url: `${app.forum.attribute('apiUrl')}/coworkingview/rates`,
        params,
        errorHandler() {},
      })
      .catch((error) => {
        pending.delete(key);
        throw error;
      });
    pending.set(key, request);
  }
  return pending.get(key);
}
