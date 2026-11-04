# CoworkingView Workplace

Kimai plugin `CoworkingViewBundle` for freelancers who record time from more than one place. A timesheet or a project can be tagged with a workplace: home, office, or coworking. The report **Hours by workplace** sums those hours.

The plugin does not download or display prices. The [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) is a separate dataset.

No account and no API key. The plugin code is MIT.

Compatible with Kimai 2.60 or newer, on PHP 8.2 or newer. No database migration and no core patches. The workplace is stored in Kimai's existing timesheet and project meta fields.

## Install

The directory inside `var/plugins/` must be named `CoworkingViewBundle`. Kimai rejects a directory name that still has a version suffix.

From a GitHub release tagged `kimai-v*`, download `CoworkingViewBundle-<version>.zip`. The archive contains one top-level folder, `CoworkingViewBundle/`.

```console
cd /path/to/kimai/var/plugins
unzip CoworkingViewBundle-0.1.0.zip
```

From this repository, copy this directory and rename it:

```console
cp -a kimai-plugin /path/to/kimai/var/plugins/CoworkingViewBundle
```

Reload the cache from the Kimai directory:

```console
bin/console cache:clear
```

Kimai lists the plugin as **CoworkingView Workplace** under System → Plugins. The homepage link on that screen is [https://coworkingview.com](https://coworkingview.com).

## Use

On a timesheet, or on a project, set **Workplace** to Home, Office, or Coworking. The field is optional. It is shown on the create and edit forms, in the timesheet and project tables, in quick entry, and in exports.

A workplace set on the timesheet is the one the report uses. When the timesheet has none, the report uses the project workplace. When neither is set, the hours stay in **Not set**.

Open **Reporting → Hours by workplace**. The permission is `view_reporting`, the same one Kimai uses for its own reports. The default range is the current month. Change the range in the filter. A timesheet counts in the range of its start, which is how the timesheet screen filters. A running entry counts the duration up to now.

You see the timesheets Kimai already lets you see. With the permission `view_other_timesheet`, the filter can be limited to one user.

The plugin does not change rates.

## Tests

From this directory, with PHP 8.2 or newer and Composer:

```console
composer install
composer lint
composer test
```

`composer lint` runs `php -l` and checks the bundle layout Kimai loads: the `KimaiPlugin` namespace, `PluginInterface`, `composer.json` (`type` `kimai-plugin`, `extra.kimai.require`, `extra.kimai.name`), the extension, the locale-prefixed routes, and the English translation file.

The unit tests cover workplace values and the hour totals. They do not boot Kimai and they do not use the network.

A listing for the Kimai Marketplace is prepared in [store-listing/](store-listing/README.md). That pull request is not part of this repository.

## Licence

The plugin is [MIT](LICENSE).

Homepage: [https://coworkingview.com](https://coworkingview.com).
