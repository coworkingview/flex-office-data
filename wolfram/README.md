# FlexOfficePriceIndex

`FlexOfficePriceIndex[city]` and `FlexOfficePriceIndex[city, product]` return [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) figures for a flex desk, a fixed desk and a private office: median, p25, p75, min and max, in EUR per month. They read the public API [https://api.coworkingview.com/v1/market/rates](https://api.coworkingview.com/v1/market/rates). Documentation: [https://coworkingview.com/en/api](https://coworkingview.com/en/api).

## Usage

```wolfram
Get["FlexOfficePriceIndex.wl"]

FlexOfficePriceIndex["Berlin"]

FlexOfficePriceIndex["Berlin", "PrivateOffice"]
```

`FlexOfficePriceIndex[city]` returns a `Dataset` with those statistics for `"FlexDesk"`, `"FixedDesk"` and `"PrivateOffice"`. `FlexOfficePriceIndex[city, product]` returns the median as a euro `Quantity`.

[`FlexOfficePriceIndex-definition.nb`](FlexOfficePriceIndex-definition.nb) is the Wolfram Function Repository definition notebook.

[`deploy-definition.wl`](deploy-definition.wl) rebuilds that notebook's code cells in Wolfram Cloud, deploys `FlexOfficePriceIndex-definition-v6.nb` and checks the deployed copy.

## Data licence

Price Index data is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
