# CoworkingView

Swift client for the public API of [CoworkingView](https://coworkingview.com).

It reads the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) and searches the coworking catalogue. No API key. The only dependency is Foundation (`URLSession`). On Linux, `URLSession` comes from `FoundationNetworking`. Nothing is downloaded when the module is imported.

Price Index figures are open data from CoworkingView under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The code is MIT.

| | |
|---|---|
| API | `https://api.coworkingview.com` |
| API reference | <https://coworkingview.com/en/api> |
| Platforms | iOS 13, macOS 10.15, tvOS 13, watchOS 6, Linux |
| Swift | 5.9 and later |

## Install

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/coworkingview/coworkingview-swift.git", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: ["CoworkingView"]),
]
```

Until the `0.1.0` tag exists on that repository, point the dependency at a local checkout of this directory.

### CocoaPods

```ruby
pod 'CoworkingView', '~> 0.1.0'
```

To try the sources before they are on trunk:

```ruby
pod 'CoworkingView', :path => '.'
```

Publishing steps are in [docs/SWIFT-CHECKLIST.md](docs/SWIFT-CHECKLIST.md). CocoaPods trunk stops accepting new pods on 2026-12-02.

## Usage

```swift
import CoworkingView

let client = try Client()

let berlin = try await client.rates(city: "berlin")
for rate in berlin.data {
    print(rate.product, rate.unit ?? "", rate.medianText, rate.currency, "n=\(rate.sampleSize)")
}
// Print this next to any figure you republish. The index is CC BY 4.0.
print(berlin.attribution ?? "")

let rooms = try await client.spaces(city: "madrid", product: "meeting_room", limit: 20)
for room in rooms.data {
    print(room.title, room.url)
}

let space = try await client.space(slug: "sankt-oberholz-rosenthaler-berlin")
for offer in space.data.pricing {
    // price is nil when the operator quotes on request. It is not zero.
    print(offer.product, offer.priceText ?? "on request", offer.currency ?? "")
}
```

`Client()` talks to `https://api.coworkingview.com`, or to whatever `COWORKINGVIEW_API_URL` is set to. The initializer changes the base URL, the timeout (default 20 seconds), the `User-Agent` and the default locale (`en`, `es` or `de`).

```swift
let client = try Client(
    timeout: 5,
    userAgent: "my-research-project/1.0 (me@example.org)",
    locale: "de"
)
```

On HTTP 429 or 5xx the client waits `Retry-After` seconds (else `RateLimit-Reset`, else 2 seconds, never more than 10) and retries once. The API allows 120 requests per minute per IP. Responses are cacheable for 10 minutes.

### What you can ask for

| Parameter | Values |
|---|---|
| locale | `en` (default), `es`, `de` |
| currency | `EUR`, `GBP`, `USD`, `CHF`, `AED`, `VES` (any case). `VES` is sent through; the API answers 400 where it cannot convert |
| product | `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, `membership` |
| sort | `random` (default), `price-asc`, `date-desc`, `date-asc` |

`rates` and `cities` call `GET /v1/market/rates`. `spaces` calls `GET /v1/properties` and follows pages until `limit` rows (default 50, maximum 200). `space` calls `GET /v1/properties/{slug}`.

A new Price Index aggregate shows up in `rates` without a library update. Products this version does not name a unit for come back with `unit == nil`.

`spaces` does not return descriptions, photos or logos. Those belong to the operators. Link to `url` instead of copying the catalogue. The catalogue notice is `Dataset.notice`.

## Data

Figures come from operator-published prices of the spaces listed on [CoworkingView](https://coworkingview.com). `asOf` on a Price Index result says when the index was computed. Keep `attribution` with anything you publish. The licence URL is `license` (`licenseUrl` on the response).

Maintained by [CoworkingView](https://coworkingview.com).
