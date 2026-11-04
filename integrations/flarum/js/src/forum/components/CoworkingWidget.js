import app from 'flarum/forum/app';
import Component from 'flarum/common/Component';
import LoadingIndicator from 'flarum/common/components/LoadingIndicator';
import { errorText, priceLine, productLabel, spreadLine, translate } from '../format';
import { loadRates } from '../loadRates';

const HOME = 'https://coworkingview.com';
const INDEX = 'https://coworkingview.com/en/tools/price-index';
const LICENSE = 'https://creativecommons.org/licenses/by/4.0/';

export function widgetEnabled() {
  const flag = app.forum.attribute('coworkingview.showWidget');
  return flag !== false && flag !== 0 && flag !== '0' && flag !== 'false';
}

function credit(includeLicense) {
  return (
    <p className="CoworkingViewCard-credit">
      <a href={HOME} rel="noopener noreferrer">
        CoworkingView
      </a>
      {includeLicense ? ' · ' : null}
      {includeLicense ? (
        <a href={LICENSE} rel="noopener noreferrer">
          CC BY 4.0
        </a>
      ) : null}
    </p>
  );
}

function card(payload) {
  if (!payload || payload.ok !== true) {
    return (
      <aside className="CoworkingViewCard">
        <p className="CoworkingViewCard-error">{errorText(payload && payload.code)}</p>
        {credit(false)}
      </aside>
    );
  }

  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  const date = payload.asOf ? String(payload.asOf).slice(0, 10) : '';

  return (
    <aside className="CoworkingViewCard" data-ready="1">
      <p className="CoworkingViewCard-city">
        <a href={INDEX} rel="noopener noreferrer">
          {payload.cityName || payload.citySlug || ''}
        </a>
      </p>
      {date ? <p className="CoworkingViewCard-asof">{translate('as_of', { date })}</p> : null}
      {rows.length === 0 ? <p className="CoworkingViewCard-empty">{translate('empty')}</p> : null}
      {rows.length > 0 ? (
        <ul className="CoworkingViewCard-rows">
          {rows.map((row) => {
            const spread = spreadLine(row);
            return (
              <li className="CoworkingViewCard-row" key={row.product}>
                <span className="CoworkingViewCard-product">{productLabel(row.product)}</span>
                <span className="CoworkingViewCard-price">{priceLine(row)}</span>
                {spread ? <span className="CoworkingViewCard-spread">{spread}</span> : null}
                {typeof row.sampleSize === 'number' ? (
                  <span className="CoworkingViewCard-sample">{translate('sample', { count: String(row.sampleSize) })}</span>
                ) : null}
                {row.lowConfidence === true ? <span className="CoworkingViewCard-low">{translate('low_confidence')}</span> : null}
              </li>
            );
          })}
        </ul>
      ) : null}
      {payload.attribution ? <p className="CoworkingViewCard-attribution">{payload.attribution}</p> : null}
      {credit(true)}
    </aside>
  );
}

export default class CoworkingWidget extends Component {
  oninit(vnode) {
    super.oninit(vnode);
    this.loading = true;
    this.failed = false;
    this.payload = null;

    const city = app.forum.attribute('coworkingview.city') || 'berlin';
    const locale = app.forum.attribute('coworkingview.locale') || 'en';
    const product = app.forum.attribute('coworkingview.product') || 'all';

    loadRates(city, product, locale)
      .then((payload) => {
        this.payload = payload;
        this.loading = false;
        m.redraw();
      })
      .catch(() => {
        this.failed = true;
        this.loading = false;
        m.redraw();
      });
  }

  view() {
    return (
      <div className="CoworkingViewWidget">
        <h3 className="CoworkingViewWidget-title">{app.translator.trans('coworkingview-flarum-coworkingview.forum.widget_title')}</h3>
        {this.loading ? <LoadingIndicator /> : null}
        {this.failed ? (
          <p className="CoworkingViewCard-error">
            {app.translator.trans('coworkingview-flarum-coworkingview.forum.errors.unavailable')}
          </p>
        ) : null}
        {!this.loading && !this.failed ? card(this.payload) : null}
      </div>
    );
  }
}
