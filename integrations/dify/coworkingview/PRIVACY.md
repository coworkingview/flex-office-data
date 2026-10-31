# Privacy policy

CoworkingView maintains this plugin. Privacy questions: info@coworkingview.com. The service privacy policy is at https://coworkingview.com/en/privacy.

## What is collected

This plugin does not collect, store, or log an account, name, email address, phone number, or API key. It has no credential form and no persistent storage.

When a tool runs, it transmits the parameters of that call to the public CoworkingView API:

- Search workspaces: city slug, optional workspace type, locale, and page size
- Get workspace: listing slug and locale
- List cities: locale and optional country code

Those values are the search the user or the model asked for. The plugin does not read GPS, contacts, files, or credentials. It does not add a price, address, or other field that the API response did not contain.

## How it is used

The parameters are used only to perform that read. The JSON returned to Dify is a subset of the API response: workspace name, city, address when published, workspace type, listing URL, slug, and the citation or catalogue notice when the API sends them. Photos, logos, and descriptions are dropped.

## Where it goes

The plugin sends those parameters to one host, `https://api.coworkingview.com`, operated by CoworkingView. That host is a third-party service from the point of view of a Dify workspace. No other external service receives the query. The plugin itself does not retain the query after the tool returns.

CoworkingView's own retention and logging of public API requests are described at https://coworkingview.com/en/privacy.

## Contact

CoworkingView, info@coworkingview.com, https://coworkingview.com.
