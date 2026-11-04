import app from 'flarum/admin/app';

const PREFIX = 'coworkingview-flarum-coworkingview';

app.initializers.add(PREFIX, () => {
  const t = (key) => app.translator.trans(`${PREFIX}.admin.settings.${key}`);
  const product = (key) => app.translator.trans(`${PREFIX}.forum.products.${key}`);

  app.extensionData
    .for(PREFIX)
    .registerSetting({
      setting: 'coworkingview.city',
      type: 'text',
      label: t('city_label'),
      help: t('city_help'),
      placeholder: 'berlin',
    })
    .registerSetting({
      setting: 'coworkingview.locale',
      type: 'select',
      label: t('locale_label'),
      help: t('locale_help'),
      options: {
        en: 'English',
        de: 'Deutsch',
        es: 'Español',
      },
      default: 'en',
    })
    .registerSetting({
      setting: 'coworkingview.product',
      type: 'select',
      label: t('product_label'),
      options: {
        all: t('product_all'),
        flex_desk: product('flex_desk'),
        fix_desk: product('fix_desk'),
        private_office: product('private_office'),
        exclusive_bereich: product('exclusive_bereich'),
        day_pass: product('day_pass'),
        meeting_room: product('meeting_room'),
        event_space: product('event_space'),
        virtual_office: product('virtual_office'),
        membership: product('membership'),
      },
      default: 'all',
    })
    .registerSetting({
      setting: 'coworkingview.show_widget',
      type: 'boolean',
      label: t('widget_label'),
      help: t('widget_help'),
    });
});
