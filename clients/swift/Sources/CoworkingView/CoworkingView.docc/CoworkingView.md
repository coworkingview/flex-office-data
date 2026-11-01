# ``CoworkingView``

A Swift client for the public [CoworkingView](https://coworkingview.com) API.

## Overview

Read the CoworkingView Price Index and search the coworking catalogue. The API at `https://api.coworkingview.com` is public and needs no key. Calls use `async`/`await` and `URLSession`.

```swift
let client = try Client()
let berlin = try await client.rates(city: "berlin")
print(berlin.attribution ?? "")
```

Price Index figures are CC BY 4.0 data from CoworkingView. Keep ``Dataset/attribution`` with anything you republish. Catalogue names and prices are for search and reference. Descriptions, photos and logos are not part of this client.

The HTTP reference is [coworkingview.com/en/api](https://coworkingview.com/en/api).

## Topics

### Calling the API

- ``Client``
- ``Dataset``

### Price Index

- ``Rate``
- ``City``

### Catalogue

- ``Listing``
- ``Space``
- ``PricingOption``

### Errors

- ``CoworkingViewError``
- ``APIError``
- ``FieldError``
