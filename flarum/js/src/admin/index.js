import app from 'flarum/admin/app';

app.initializers.add('coworkingview/flarum-coworkingview', () => {
  app.extensionData.for('coworkingview-coworkingview').registerSetting({
    setting: 'coworkingview.default_locale',
    label: app.translator.trans('coworkingview-coworkingview.admin.settings.default_locale_label'),
    help: app.translator.trans('coworkingview-coworkingview.admin.settings.default_locale_help'),
    type: 'select',
    options: {
      de: 'Deutsch',
      es: 'Español',
      en: 'English',
    },
    default: 'de',
  });
});
