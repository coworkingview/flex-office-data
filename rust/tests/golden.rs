//! Parsing every fixture in `spec/fixtures/` must reproduce `spec/golden/`
//! byte for byte (the reference is `spec/tools/make_golden.py`).

mod common;

use common::{fixture, golden};
use coworkingview::{csv, parse, Locale, Product, Unit};

fn to_csv<R: csv::CsvRow>(rows: &[R]) -> String {
    let mut out = Vec::new();
    csv::write(&mut out, rows).unwrap();
    String::from_utf8(out).unwrap()
}

#[test]
fn rates_match_golden() {
    let ds = parse::rates(&fixture("market_rates.json")).unwrap();
    assert_eq!(to_csv(&ds), golden("rates.csv"));
    assert!(ds
        .attribution
        .as_deref()
        .unwrap()
        .starts_with("Source: CoworkingView Price Index"));
    assert_eq!(
        ds.license.as_deref(),
        Some("https://creativecommons.org/licenses/by/4.0/")
    );
    assert_eq!(ds.as_of.as_deref(), Some("2026-10-27T21:06:48.313Z"));
}

#[test]
fn cities_match_golden() {
    let ds = parse::cities(&fixture("market_rates.json")).unwrap();
    assert_eq!(to_csv(&ds), golden("cities.csv"));
    assert!(!ds.last().unwrap().published);
}

#[test]
fn spaces_match_golden() {
    let ds = parse::spaces(&fixture("properties_berlin.json"), Locale::En).unwrap();
    assert_eq!(to_csv(&ds), golden("spaces.csv"));
    assert!(ds
        .attribution
        .as_deref()
        .unwrap()
        .contains("Coworking spaces in Berlin"));
    assert!(ds
        .notice
        .as_deref()
        .unwrap()
        .contains("Systematic extraction"));
    assert_eq!(ds.as_of.as_deref(), Some("2026-10-27"));
}

#[test]
fn space_pricing_matches_golden() {
    let ds = parse::space(&fixture("property_detail.json"), Locale::En).unwrap();
    assert_eq!(to_csv(&ds.pricing), golden("space_pricing.csv"));
    assert_eq!(ds.slug, "sankt-oberholz-rosenthaler-berlin");
    assert_eq!(
        ds.url,
        "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin"
    );
    assert_eq!(
        ds.address.as_deref(),
        Some("Rosenthaler Straße 72a, 10119 Berlin, Germany")
    );
    assert_eq!(ds.amenities.len(), 9);
    assert_eq!(ds.market_verdict.as_deref(), Some("around"));
    assert!(ds.attribution.is_some() && ds.notice.is_some());
}

#[test]
fn space_urls_follow_locale() {
    let es = parse::spaces(&fixture("properties_berlin.json"), Locale::Es).unwrap();
    assert!(es[0]
        .url
        .starts_with("https://coworkingview.com/es/oficina/"));
    let de = parse::spaces(&fixture("properties_berlin.json"), Locale::De).unwrap();
    assert!(de[0].url.starts_with("https://coworkingview.com/de/buero/"));
}

#[test]
fn converted_currency_fixture_parses() {
    let ds = parse::rates(&fixture("market_rates_berlin_usd.json")).unwrap();
    assert!(!ds.is_empty());
    assert!(ds
        .iter()
        .all(|r| r.currency == "USD" && r.city_slug == "berlin"));
    let products: Vec<_> = ds.iter().map(|r| (r.product.clone(), r.unit)).collect();
    assert_eq!(products[0], (Product::FlexDesk, Some(Unit::Month)));
    assert!(products.contains(&(Product::DayPass, Some(Unit::Day))));
    assert!(products.contains(&(Product::MeetingRoom, Some(Unit::Hour))));
}

#[test]
fn empty_search_parses() {
    let ds = parse::spaces(&fixture("properties_empty.json"), Locale::En).unwrap();
    assert!(ds.is_empty());
    assert_eq!(to_csv(&ds).lines().count(), 1, "header only");
    assert!(ds.attribution.is_some());
}

#[test]
fn problem_fixture_is_not_a_dataset() {
    let err = parse::rates(&fixture("error_validation.json")).unwrap_err();
    assert_eq!(err.code(), "BAD_RESPONSE");
}
