// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.model;

import std.typecons : Nullable;

/**
A result plus the credit that has to travel with it.

Price Index calls set `attribution`, `license` and `asOf`. Catalogue calls set
`attribution` (the citation text), `notice` and, for a search, `total`.
*/
struct Dataset(T)
{
    /// The rows, or the one space.
    T data;
    /// Text to show next to anything you republish.
    string attribution;
    /// Licence URL for Price Index figures (`licenseUrl` on the response).
    string license;
    /// When the index was computed (`asOf`), as the API wrote it.
    string asOf;
    /// Catalogue notice. Descriptions, photos and logos are not included.
    string notice;
    /// `pagination.total` from the first page of a search. Null when the page had none.
    Nullable!long total;
}

/// One Price Index figure: a published city and a product.
struct Rate
{
    string citySlug;
    string cityName;
    /// Null when the city object has no `countryCode`.
    string countryCode;
    string currency;
    /// Product code, for example `flex_desk`. Unknown products pass through.
    string product;
    /// `month`, `day`, `hour`, or null for an aggregate this version does not name.
    string unit;
    double median;
    /// Exact `median` token from the API (`214`, not `214.0`).
    string medianText;
    Nullable!double p25;
    string p25Text;
    Nullable!double p75;
    string p75Text;
    long sampleSize;
    Nullable!long propertyCount;
    Nullable!long operatorCount;
    /// True when `sampleSize` is below 10.
    bool lowConfidence;
    string asOf;
}

/// One city covered by the Price Index.
struct City
{
    string citySlug;
    string cityName;
    string countryCode;
    /// Null for an unpublished city that did not send one.
    string currency;
    /// True for `cities`, false for `unpublished`.
    bool published;
    Nullable!long propertyCount;
    Nullable!long operatorCount;
    Nullable!double entryMedian;
    string entryMedianText;
    Nullable!double entryMin;
    string entryMinText;
    Nullable!double entryMax;
    string entryMaxText;
    Nullable!double p25;
    string p25Text;
    Nullable!double p75;
    string p75Text;
    Nullable!long sampleSize;
    string asOf;
}

/// One catalogue row from `Client.spaces`.
struct Listing
{
    string slug;
    string title;
    string citySlug;
    string zoneSlug;
    string operatorSlug;
    string operatorName;
    string countryCode;
    Nullable!double lat;
    string latText;
    Nullable!double lng;
    string lngText;
    Nullable!bool featured;
    /// `below`, `around` or `above`, when the API sent a market position.
    string marketVerdict;
    Nullable!double marketMedian;
    string marketMedianText;
    Nullable!long marketSampleSize;
    /// Listing page on coworkingview.com.
    string url;
    string updatedAt;
}

/// One price option on a space. `price` is null when the operator quotes on request.
struct PricingOption
{
    string product;
    string title;
    Nullable!double price;
    string priceText;
    string currency;
    string billingPeriod;
    bool priceOnRequest;
    Nullable!long minCapacity;
    Nullable!long maxCapacity;
}

/// One space and its pricing table. Descriptions, photos and logos are not included.
struct Space
{
    string slug;
    string title;
    string citySlug;
    string zoneSlug;
    string operatorSlug;
    string operatorName;
    string countryCode;
    Nullable!double lat;
    string latText;
    Nullable!double lng;
    string lngText;
    Nullable!bool featured;
    string marketVerdict;
    Nullable!double marketMedian;
    string marketMedianText;
    Nullable!long marketSampleSize;
    /// `webUrl` when the API sent one, otherwise the listing page for the requested locale.
    string url;
    string updatedAt;
    string address;
    /// Integer `capacity` from the detail, when the operator published one.
    Nullable!long capacity;
    string[] amenities;
    PricingOption[] pricing;
    string attribution;
    string notice;
}
