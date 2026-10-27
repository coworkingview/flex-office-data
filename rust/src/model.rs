//! Typed rows returned by [`Client`](crate::Client).
//!
//! Field names and order follow the shared specification of the
//! flex-office-data kit, so the CSV written by this crate is identical to the
//! one written by the Python and R packages.

use std::ops::Deref;

use serde::Serialize;

use crate::types::{Product, Unit};

/// Rows (or one record) plus the attribution that must travel with them.
///
/// The Price Index is licensed CC BY 4.0: when you publish figures from
/// [`rates`](crate::Client::rates) or [`cities`](crate::Client::cities),
/// publish [`attribution`](Dataset::attribution) with them. Catalogue results
/// carry the citation text and the catalogue notice instead.
///
/// `Dataset<T>` dereferences to `T`, so `for row in client.rates()?.iter()`
/// works directly.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[non_exhaustive]
pub struct Dataset<T> {
    /// The attribution text to publish alongside the data.
    pub attribution: Option<String>,
    /// Licence URL (Price Index only), e.g.
    /// `https://creativecommons.org/licenses/by/4.0/`.
    pub license: Option<String>,
    /// When the figures were computed (Price Index, ISO 8601) or accessed
    /// (catalogue, `YYYY-MM-DD`).
    pub as_of: Option<String>,
    /// Terms of use for catalogue content (catalogue only).
    pub notice: Option<String>,
    /// The rows or record.
    pub data: T,
}

impl<T> Dataset<T> {
    /// Unwraps the data, dropping the attribution.
    pub fn into_inner(self) -> T {
        self.data
    }

    pub(crate) fn map<U>(self, f: impl FnOnce(T) -> U) -> Dataset<U> {
        Dataset {
            attribution: self.attribution,
            license: self.license,
            as_of: self.as_of,
            notice: self.notice,
            data: f(self.data),
        }
    }
}

impl<T> Deref for Dataset<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.data
    }
}

/// One Price Index figure: a city × product.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[non_exhaustive]
pub struct RateRow {
    /// City slug, e.g. `"berlin"`.
    pub city_slug: String,
    /// City name in the requested locale.
    pub city_name: String,
    /// ISO 3166-1 alpha-2 country code.
    pub country_code: Option<String>,
    /// Currency of the amounts.
    pub currency: String,
    /// The product.
    pub product: Product,
    /// What one price buys: a month, a day or an hour.
    pub unit: Option<Unit>,
    /// Median price.
    pub median: f64,
    /// 25th percentile, when published.
    pub p25: Option<f64>,
    /// 75th percentile, when published.
    pub p75: Option<f64>,
    /// Number of price points behind the figure.
    pub sample_size: u64,
    /// Number of spaces behind the figure.
    pub property_count: Option<u64>,
    /// Number of operators behind the figure.
    pub operator_count: Option<u64>,
    /// `true` when fewer than 10 price points: treat as indicative.
    pub low_confidence: bool,
    /// When the index was computed (ISO 8601).
    pub as_of: String,
}

/// One city of the Price Index.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[non_exhaustive]
pub struct CityRow {
    /// City slug.
    pub city_slug: String,
    /// City name in the requested locale.
    pub city_name: String,
    /// ISO 3166-1 alpha-2 country code.
    pub country_code: Option<String>,
    /// Currency of the amounts.
    pub currency: Option<String>,
    /// `false` for cities with too little data to publish figures.
    pub published: bool,
    /// Spaces with prices in the city.
    pub property_count: Option<u64>,
    /// Operators with prices in the city.
    pub operator_count: Option<u64>,
    /// Median of each space's cheapest monthly option.
    pub entry_median: Option<f64>,
    /// Cheapest monthly entry price.
    pub entry_min: Option<f64>,
    /// Most expensive monthly entry price.
    pub entry_max: Option<f64>,
    /// City-level 25th percentile.
    pub p25: Option<f64>,
    /// City-level 75th percentile.
    pub p75: Option<f64>,
    /// City-level number of price points.
    pub sample_size: Option<u64>,
    /// When the index was computed (ISO 8601).
    pub as_of: String,
}

/// One space in catalogue search results.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[non_exhaustive]
pub struct SpaceRow {
    /// Space slug; pass it to [`Client::space`](crate::Client::space).
    pub slug: String,
    /// Space name.
    pub title: String,
    /// City slug.
    pub city_slug: Option<String>,
    /// Zone (district) slug.
    pub zone_slug: Option<String>,
    /// Operator slug.
    pub operator_slug: Option<String>,
    /// Operator name.
    pub operator_name: Option<String>,
    /// ISO 3166-1 alpha-2 country code.
    pub country_code: Option<String>,
    /// Latitude.
    pub lat: Option<f64>,
    /// Longitude.
    pub lng: Option<f64>,
    /// Whether the space is featured.
    pub featured: Option<bool>,
    /// Price versus the city median: `below`, `around` or `above`.
    pub market_verdict: Option<String>,
    /// The city median the verdict compares against.
    pub market_median: Option<f64>,
    /// Price points behind that median.
    pub market_sample_size: Option<u64>,
    /// The space's page on coworkingview.com.
    pub url: String,
    /// Last update (ISO 8601).
    pub updated_at: Option<String>,
}

/// One space with its address, amenities and pricing table.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[non_exhaustive]
pub struct Space {
    /// Space slug.
    pub slug: String,
    /// Space name.
    pub title: String,
    /// City slug.
    pub city_slug: Option<String>,
    /// Zone (district) slug.
    pub zone_slug: Option<String>,
    /// Operator slug.
    pub operator_slug: Option<String>,
    /// Operator name.
    pub operator_name: Option<String>,
    /// ISO 3166-1 alpha-2 country code.
    pub country_code: Option<String>,
    /// Latitude.
    pub lat: Option<f64>,
    /// Longitude.
    pub lng: Option<f64>,
    /// Whether the space is featured.
    pub featured: Option<bool>,
    /// Price versus the city median: `below`, `around` or `above`.
    pub market_verdict: Option<String>,
    /// The city median the verdict compares against.
    pub market_median: Option<f64>,
    /// Price points behind that median.
    pub market_sample_size: Option<u64>,
    /// The space's page on coworkingview.com (`webUrl`).
    pub url: String,
    /// Last update (ISO 8601).
    pub updated_at: Option<String>,
    /// Street address.
    pub address: Option<String>,
    /// Total capacity (people), when known.
    pub capacity: Option<u64>,
    /// Amenity keys, e.g. `"wifi"`, `"meeting_rooms"`.
    pub amenities: Vec<String>,
    /// The pricing table, one row per offer.
    pub pricing: Vec<PricingRow>,
}

/// One offer of a space.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[non_exhaustive]
pub struct PricingRow {
    /// The product.
    pub product: Product,
    /// The operator's name for the offer.
    pub title: String,
    /// Price; `None` when on request.
    pub price: Option<f64>,
    /// Currency of the price; `None` when on request.
    pub currency: Option<String>,
    /// Billing period as the API states it, e.g. `"month"`, `"day"`, `"once"`.
    pub billing_period: String,
    /// `true` when the operator quotes the price on request.
    pub price_on_request: bool,
    /// Minimum people, when stated.
    pub min_capacity: Option<u64>,
    /// Maximum people, when stated.
    pub max_capacity: Option<u64>,
}
