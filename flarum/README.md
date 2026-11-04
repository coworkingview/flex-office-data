# CoworkingView for Flarum

A [Flarum](https://flarum.org) 1.x extension that turns a BBCode tag into a small card linking to a city hub on [«CoworkingView»](https://coworkingview.com).

The card is one link. Its text names [«CoworkingView»](https://coworkingview.com) and the city, and the address is one of these hubs (each returned HTTP 200 when checked on 4 November 2026):

- [Berlin](https://coworkingview.com/de/coworking/berlin)
- [Hamburg](https://coworkingview.com/de/coworking/hamburg)
- [München](https://coworkingview.com/de/coworking/munich)
- [Barcelona](https://coworkingview.com/es/coworking/barcelona)
- [Madrid](https://coworkingview.com/es/coworking/madrid)

`city="muenchen"` and `city="München"` use the München hub above. `https://coworkingview.com/de/coworking/muenchen` answers with a redirect, so it is not used. Any other city value, or a tag with no city, links to [https://coworkingview.com](https://coworkingview.com). The city value is not appended to a URL.

## Install

On a Flarum 1.8 or newer forum:

```bash
composer require coworkingview/flarum-coworkingview
php flarum cache:clear
```

Enable **CoworkingView** in the admin extension list.

Source: [coworkingview/flarum-coworkingview](https://github.com/coworkingview/flarum-coworkingview). `composer.json` is at the root of that repository. This `flarum/` directory is the same package. It has not been submitted to Packagist. Until it is listed there, require it from the Git repository:

```bash
composer config repositories.coworkingview vcs https://github.com/coworkingview/flarum-coworkingview
composer require coworkingview/flarum-coworkingview:^0.1.0
```

## Usage

In a post:

```text
[coworkingview city="berlin"]
```

The same form works for `hamburg`, `munich`, `barcelona`, and `madrid`.

```text
[coworkingview city="hamburg"]
[coworkingview city="munich"]
[coworkingview city="barcelona"]
[coworkingview city="madrid"]
```

A tag with no city links to the CoworkingView homepage:

```text
[coworkingview]
```

The card is a real link with visible text, a focus outline, and styles taken from the forum palette. It does not open a new tab.

### Default language

In the extension settings, **Default language** chooses the sentence on the card: Deutsch, Español, or English. The default is Deutsch. The setting does not change which hub a city links to. Berlin, Hamburg, and München stay on the German hubs, and Barcelona and Madrid stay on the Spanish hubs. Clear the Flarum cache after changing formatter configuration; the language setting itself applies the next time a post is shown.

## Extiverse

The `composer.json` `type` is `flarum-extension`, and `extra.flarum-extension` sets the title **CoworkingView**, the category `feature`, and a Font Awesome icon. That is the metadata Extiverse reads from Packagist. Nothing has been submitted to Packagist or Extiverse.

## Affiliation

This extension was built with AI assistance and is maintained by [CoworkingView](https://coworkingview.com).

## License

MIT. Copyright (c) 2026 CoworkingView.
