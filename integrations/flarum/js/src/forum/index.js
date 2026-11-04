import app from 'flarum/forum/app';
import { extend } from 'flarum/common/extend';
import IndexPage from 'flarum/forum/components/IndexPage';
import DiscussionPage from 'flarum/forum/components/DiscussionPage';
import CommentPost from 'flarum/forum/components/CommentPost';
import ComposerPostPreview from 'flarum/forum/components/ComposerPostPreview';
import CoworkingWidget, { widgetEnabled } from './components/CoworkingWidget';
import { fillElement } from './cardDom';
import { loadRates } from './loadRates';

export { default as CoworkingWidget } from './components/CoworkingWidget';

function scan(root) {
  if (!root || !root.querySelectorAll) {
    return;
  }
  root.querySelectorAll('.CoworkingViewCard').forEach((card) => {
    if (card.getAttribute('data-ready') === '1' || card.getAttribute('data-coworking-loading') === '1') {
      return;
    }
    const city = card.getAttribute('data-city');
    if (!city) {
      return;
    }
    card.setAttribute('data-coworking-loading', '1');
    const product = card.getAttribute('data-product') || '';
    const locale = card.getAttribute('data-locale') || app.forum.attribute('coworkingview.locale') || 'en';
    loadRates(city, product, locale)
      .then((payload) => {
        fillElement(card, payload);
      })
      .catch(() => {
        fillElement(card, { ok: false, code: 'unavailable' });
      });
  });
}

app.initializers.add('coworkingview-flarum-coworkingview', () => {
  extend(IndexPage.prototype, 'sidebarItems', function (items) {
    if (!widgetEnabled()) {
      return;
    }
    items.add('coworkingview', <CoworkingWidget />, -10);
  });

  extend(DiscussionPage.prototype, 'sidebarItems', function (items) {
    if (!widgetEnabled()) {
      return;
    }
    items.add('coworkingview', <CoworkingWidget />, 10);
  });

  extend(CommentPost.prototype, 'oncreate', function () {
    scan(this.element);
  });
  extend(CommentPost.prototype, 'onupdate', function () {
    scan(this.element);
  });

  extend(ComposerPostPreview.prototype, 'oncreate', function () {
    const dom = this.element;
    this.coworkingTimer = setInterval(() => scan(dom), 250);
  });
  extend(ComposerPostPreview.prototype, 'onremove', function () {
    clearInterval(this.coworkingTimer);
  });
});
