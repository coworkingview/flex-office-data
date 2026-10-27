//! Parsers from raw API responses to rows, for when you already have the JSON
//! (a cached response, a file, another HTTP client).
//!
//! Each function takes the full response body — the `{ "data", "meta" }`
//! envelope — exactly as the API returned it.
//!
//! ```
//! let body = r#"{"data":{"asOf":"2026-10-27T21:06:48.313Z","attribution":"Source: CoworkingView Price Index","licenseUrl":"https://creativecommons.org/licenses/by/4.0/","cities":[{"city":{"slug":"berlin","name":"Berlin"},"countryCode":"DE","currency":"EUR","figures":[{"optionType":"flex_desk","median":{"amount":214,"currency":"EUR"},"sampleSize":72}]}]},"meta":{"contractVersion":"1.0.0"}}"#;
//! let rates = coworkingview::parse::rates(body)?;
//! assert_eq!(rates[0].median, 214.0);
//! assert_eq!(rates.attribution.as_deref(), Some("Source: CoworkingView Price Index"));
//! # Ok::<(), coworkingview::Error>(())
//! ```

use serde_json::{Map, Value};

use crate::error::{Error, Result};
use crate::model::{CityRow, Dataset, PricingRow, RateRow, Space, SpaceRow};
use crate::types::{Locale, Product, Unit};

/// Figures with fewer price points than this are flagged `low_confidence`.
pub const LOW_CONFIDENCE_BELOW: u64 = 10;

/// Parses a `GET /v1/market/rates` response into Price Index rows (SPEC §3).
pub fn rates(body: &str) -> Result<Dataset<Vec<RateRow>>> {
    let env = envelope(body)?;
    let data = obj(&env.data, "data")?;
    let as_of = req_str(data, "asOf")?;
    let mut rows = Vec::new();
    for city in arr(data, "cities")? {
        let city = obj(city, "cities[]")?;
        let c = obj(req(city, "city")?, "city")?;
        let city_slug = req_str(c, "slug")?;
        let city_name = req_str(c, "name")?;
        let country_code = opt_str(city, "countryCode");
        let currency = req_str(city, "currency")?;

        let row = |product: Product, unit: Option<Unit>, stat: &Map<String, Value>| {
            let sample_size = req_u64(stat, "sampleSize")?;
            Ok::<_, Error>(RateRow {
                city_slug: city_slug.clone(),
                city_name: city_name.clone(),
                country_code: country_code.clone(),
                currency: currency.clone(),
                product,
                unit,
                median: req_amount(stat, "median")?,
                p25: amount(stat, "p25"),
                p75: amount(stat, "p75"),
                sample_size,
                property_count: opt_u64(stat, "propertyCount"),
                operator_count: opt_u64(stat, "operatorCount"),
                low_confidence: sample_size < LOW_CONFIDENCE_BELOW,
                as_of: as_of.clone(),
            })
        };

        // 1–2. Monthly figures: `figures`, else `byType`.
        let monthly = [city.get("figures"), city.get("byType")]
            .into_iter()
            .flatten()
            .filter_map(Value::as_array)
            .find(|a| !a.is_empty());
        for item in monthly.into_iter().flatten() {
            let item = obj(item, "figures[]")?;
            let product = Product::from_api(&req_str(item, "optionType")?);
            rows.push(row(product, Some(Unit::Month), item)?);
        }

        // 3. Every top-level aggregate (`dayPass`, `meetingRoom`, …).
        for (key, value) in city {
            let Some(stat) = value.as_object() else {
                continue;
            };
            if !(stat.contains_key("median") && stat.contains_key("sampleSize")) {
                continue;
            }
            let product = Product::from_api(&snake_case(key));
            let unit = Unit::for_stat(&product);
            rows.push(row(product, unit, stat)?);
        }
    }
    rows.sort_by(|a, b| {
        (a.city_slug.as_str(), a.product.sort_key())
            .cmp(&(b.city_slug.as_str(), b.product.sort_key()))
    });
    Ok(Dataset {
        attribution: opt_str(data, "attribution"),
        license: opt_str(data, "licenseUrl"),
        as_of: Some(as_of),
        notice: None,
        data: rows,
    })
}

/// Parses a `GET /v1/market/rates` response into one row per city (SPEC §4).
pub fn cities(body: &str) -> Result<Dataset<Vec<CityRow>>> {
    let env = envelope(body)?;
    let data = obj(&env.data, "data")?;
    let as_of = req_str(data, "asOf")?;
    let mut rows = Vec::new();
    for city in arr(data, "cities")? {
        let city = obj(city, "cities[]")?;
        let c = obj(req(city, "city")?, "city")?;
        rows.push(CityRow {
            city_slug: req_str(c, "slug")?,
            city_name: req_str(c, "name")?,
            country_code: opt_str(city, "countryCode"),
            currency: Some(req_str(city, "currency")?),
            published: true,
            property_count: opt_u64(city, "propertyCount"),
            operator_count: opt_u64(city, "operatorCount"),
            entry_median: amount(city, "entryMedian"),
            entry_min: amount(city, "entryMin"),
            entry_max: amount(city, "entryMax"),
            p25: amount(city, "p25"),
            p75: amount(city, "p75"),
            sample_size: opt_u64(city, "sampleSize"),
            as_of: as_of.clone(),
        });
    }
    let unpublished = data.get("unpublished").and_then(Value::as_array);
    for city in unpublished.into_iter().flatten() {
        let city = obj(city, "unpublished[]")?;
        let c = obj(req(city, "city")?, "city")?;
        rows.push(CityRow {
            city_slug: req_str(c, "slug")?,
            city_name: req_str(c, "name")?,
            country_code: opt_str(city, "countryCode"),
            currency: opt_str(city, "currency"),
            published: false,
            property_count: None,
            operator_count: None,
            entry_median: None,
            entry_min: None,
            entry_max: None,
            p25: None,
            p75: None,
            sample_size: None,
            as_of: as_of.clone(),
        });
    }
    rows.sort_by(|a, b| (!a.published, &a.city_slug).cmp(&(!b.published, &b.city_slug)));
    Ok(Dataset {
        attribution: opt_str(data, "attribution"),
        license: opt_str(data, "licenseUrl"),
        as_of: Some(as_of),
        notice: None,
        data: rows,
    })
}

/// Parses one page of `GET /v1/properties` (SPEC §5). `locale` builds the
/// `url` column and must match the request's `locale`.
pub fn spaces(body: &str, locale: Locale) -> Result<Dataset<Vec<SpaceRow>>> {
    Ok(spaces_page(body, locale)?.dataset)
}

pub(crate) struct SpacesPage {
    pub dataset: Dataset<Vec<SpaceRow>>,
    pub page_count: Option<u64>,
    pub seed: Option<Value>,
}

pub(crate) fn spaces_page(body: &str, locale: Locale) -> Result<SpacesPage> {
    let env = envelope(body)?;
    let cards = env
        .data
        .as_array()
        .ok_or_else(|| Error::bad(200, "`data` is not an array"))?;
    let rows = cards
        .iter()
        .map(|c| {
            let c = obj(c, "data[]")?;
            let slug = req_str(c, "slug")?;
            let url = format!(
                "https://coworkingview.com/{}/{}/{}",
                locale.as_str(),
                locale.workspace_path(),
                slug
            );
            card(c, slug, url)
        })
        .collect::<Result<Vec<_>>>()?;
    let meta = env.meta.as_ref();
    let page_count = meta
        .and_then(|m| m.get("pagination"))
        .and_then(|p| p.get("pageCount"))
        .and_then(Value::as_u64);
    let seed = meta
        .and_then(|m| m.get("seed"))
        .filter(|s| !s.is_null())
        .cloned();
    Ok(SpacesPage {
        dataset: catalogue_dataset(meta, rows),
        page_count,
        seed,
    })
}

/// Parses a `GET /v1/properties/{slug}` response (SPEC §6). `locale` is used
/// for the `url` only when the response has no `webUrl`.
pub fn space(body: &str, locale: Locale) -> Result<Dataset<Space>> {
    let env = envelope(body)?;
    let d = obj(&env.data, "data")?;
    let slug = req_str(d, "slug")?;
    let url = opt_str(d, "webUrl").unwrap_or_else(|| {
        format!(
            "https://coworkingview.com/{}/{}/{}",
            locale.as_str(),
            locale.workspace_path(),
            slug
        )
    });
    let row = card(d, slug, url)?;
    let pricing = d
        .get("pricingOptions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|o| {
            let o = obj(o, "pricingOptions[]")?;
            let price = o.get("price").and_then(Value::as_object);
            Ok(PricingRow {
                product: Product::from_api(&req_str(o, "optionType")?),
                title: req_str(o, "title")?,
                price: price.map(|p| req_f64(p, "amount")).transpose()?,
                currency: price.and_then(|p| opt_str(p, "currency")),
                billing_period: req_str(o, "billingPeriod")?,
                price_on_request: req(o, "priceOnRequest")?
                    .as_bool()
                    .ok_or_else(|| Error::bad(200, "`priceOnRequest` is not a boolean"))?,
                min_capacity: opt_u64(o, "minCapacity"),
                max_capacity: opt_u64(o, "maxCapacity"),
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let amenities = d
        .get("amenities")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|a| a.as_str().map(str::to_owned))
        .collect();
    let space = Space {
        slug: row.slug,
        title: row.title,
        city_slug: row.city_slug,
        zone_slug: row.zone_slug,
        operator_slug: row.operator_slug,
        operator_name: row.operator_name,
        country_code: row.country_code,
        lat: row.lat,
        lng: row.lng,
        featured: row.featured,
        market_verdict: row.market_verdict,
        market_median: row.market_median,
        market_sample_size: row.market_sample_size,
        url: row.url,
        updated_at: row.updated_at,
        address: opt_str(d, "address"),
        capacity: opt_u64(d, "capacity"),
        amenities,
        pricing,
    };
    Ok(catalogue_dataset(env.meta.as_ref(), ()).map(|()| space))
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

struct Envelope {
    data: Value,
    meta: Option<Value>,
}

fn envelope(body: &str) -> Result<Envelope> {
    let mut v: Value = serde_json::from_str(body)
        .map_err(|e| Error::bad(200, format!("body is not JSON ({e})")))?;
    let o = v
        .as_object_mut()
        .ok_or_else(|| Error::bad(200, "body is not a JSON object"))?;
    let data = o
        .remove("data")
        .ok_or_else(|| Error::bad(200, "missing `data`"))?;
    Ok(Envelope {
        data,
        meta: o.remove("meta"),
    })
}

fn card(c: &Map<String, Value>, slug: String, url: String) -> Result<SpaceRow> {
    let sub = |k: &str, f: &str| {
        c.get(k)
            .and_then(Value::as_object)
            .and_then(|o| opt_str(o, f))
    };
    let coord = |f: &str| {
        c.get("coordinates")
            .and_then(Value::as_object)
            .and_then(|o| o.get(f))
            .and_then(Value::as_f64)
    };
    let market = c.get("marketPosition").and_then(Value::as_object);
    Ok(SpaceRow {
        title: req_str(c, "title")?,
        city_slug: sub("city", "slug"),
        zone_slug: sub("zone", "slug"),
        operator_slug: sub("operator", "slug"),
        operator_name: sub("operator", "name"),
        country_code: opt_str(c, "countryCode"),
        lat: coord("lat"),
        lng: coord("lng"),
        featured: c.get("featured").and_then(Value::as_bool),
        market_verdict: market.and_then(|m| opt_str(m, "verdict")),
        market_median: market.and_then(|m| amount(m, "median")),
        market_sample_size: market.and_then(|m| opt_u64(m, "sampleSize")),
        updated_at: opt_str(c, "updatedAt"),
        slug,
        url,
    })
}

fn catalogue_dataset<T>(meta: Option<&Value>, data: T) -> Dataset<T> {
    let citation = meta.and_then(|m| m.get("citation"));
    let field = |v: Option<&Value>, k: &str| {
        v.and_then(|v| v.get(k))
            .and_then(Value::as_str)
            .map(str::to_owned)
    };
    Dataset {
        attribution: field(citation, "text"),
        license: None,
        as_of: field(citation, "accessed"),
        notice: field(meta, "catalogueNotice"),
        data,
    }
}

/// `dayPass` → `day_pass`, matching the reference implementation.
fn snake_case(key: &str) -> String {
    let mut out = String::with_capacity(key.len() + 4);
    for (i, ch) in key.chars().enumerate() {
        if ch.is_uppercase() && i > 0 {
            out.push('_');
        }
        out.extend(ch.to_lowercase());
    }
    out
}

fn obj<'a>(v: &'a Value, what: &str) -> Result<&'a Map<String, Value>> {
    v.as_object()
        .ok_or_else(|| Error::bad(200, format!("`{what}` is not an object")))
}

fn req<'a>(o: &'a Map<String, Value>, k: &str) -> Result<&'a Value> {
    o.get(k)
        .filter(|v| !v.is_null())
        .ok_or_else(|| Error::bad(200, format!("missing `{k}`")))
}

fn arr<'a>(o: &'a Map<String, Value>, k: &str) -> Result<&'a Vec<Value>> {
    req(o, k)?
        .as_array()
        .ok_or_else(|| Error::bad(200, format!("`{k}` is not an array")))
}

fn req_str(o: &Map<String, Value>, k: &str) -> Result<String> {
    req(o, k)?
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| Error::bad(200, format!("`{k}` is not a string")))
}

fn opt_str(o: &Map<String, Value>, k: &str) -> Option<String> {
    o.get(k).and_then(Value::as_str).map(str::to_owned)
}

fn req_f64(o: &Map<String, Value>, k: &str) -> Result<f64> {
    req(o, k)?
        .as_f64()
        .ok_or_else(|| Error::bad(200, format!("`{k}` is not a number")))
}

fn req_u64(o: &Map<String, Value>, k: &str) -> Result<u64> {
    req(o, k)?
        .as_u64()
        .ok_or_else(|| Error::bad(200, format!("`{k}` is not a non-negative integer")))
}

fn opt_u64(o: &Map<String, Value>, k: &str) -> Option<u64> {
    o.get(k).and_then(Value::as_u64)
}

/// `{ "amount": 214, "currency": "EUR" }` → `214.0`.
fn amount(o: &Map<String, Value>, k: &str) -> Option<f64> {
    o.get(k)
        .and_then(|m| m.get("amount"))
        .and_then(Value::as_f64)
}

fn req_amount(o: &Map<String, Value>, k: &str) -> Result<f64> {
    let money = obj(req(o, k)?, k)?;
    req_f64(money, "amount")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snake() {
        assert_eq!(snake_case("dayPass"), "day_pass");
        assert_eq!(snake_case("meetingRoom"), "meeting_room");
        assert_eq!(snake_case("eventSpace"), "event_space");
        assert_eq!(snake_case("membership"), "membership");
    }

    #[test]
    fn new_aggregates_appear_without_a_release() {
        let body = r#"{"data":{"asOf":"x","cities":[{"city":{"slug":"a","name":"A"},"currency":"EUR",
            "byType":[{"optionType":"flex_desk","median":{"amount":100},"sampleSize":12}],
            "eventSpace":{"median":{"amount":80.5},"p25":{"amount":60},"sampleSize":4},
            "phoneBooth":{"median":{"amount":5},"sampleSize":20},
            "p25":{"amount":1}}]}}"#;
        let rows = rates(body).unwrap();
        let got: Vec<_> = rows
            .iter()
            .map(|r| {
                (
                    r.product.as_str().to_owned(),
                    r.unit,
                    r.p25,
                    r.property_count,
                )
            })
            .collect();
        assert_eq!(
            got,
            vec![
                ("flex_desk".into(), Some(Unit::Month), None, None),
                ("event_space".into(), Some(Unit::Hour), Some(60.0), None),
                ("phone_booth".into(), None, None, None),
            ]
        );
        assert!(rows[1].low_confidence);
    }

    #[test]
    fn not_json_is_bad_response() {
        let e = rates("<html>").unwrap_err();
        assert_eq!(e.code(), "BAD_RESPONSE");
    }
}
