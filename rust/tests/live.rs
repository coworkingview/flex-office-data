//! Opt-in checks against the production API. They run only with
//! `COWORKINGVIEW_LIVE_TESTS=1` and make exactly 3 requests in total — the API
//! runs on a small server, so keep it that way.

use coworkingview::{Client, Product, RatesQuery, SpacesQuery};

fn live() -> bool {
    std::env::var("COWORKINGVIEW_LIVE_TESTS").as_deref() == Ok("1")
}

#[test]
fn live_round_trip() {
    if !live() {
        eprintln!("skipped: set COWORKINGVIEW_LIVE_TESTS=1 to run (3 requests)");
        return;
    }
    let client = Client::new();

    // 1. Price Index for one city.
    let rates = client
        .rates_with(&RatesQuery::new().city("berlin"))
        .expect("rates");
    assert!(rates.iter().any(|r| r.product == Product::FlexDesk));
    assert!(rates
        .attribution
        .as_deref()
        .unwrap_or("")
        .contains("CC BY 4.0"));

    // 2. One page of search (limit ≤ 50 → one request).
    let spaces = client
        .spaces(&SpacesQuery::new().city("berlin").limit(3))
        .expect("spaces");
    assert!(!spaces.is_empty() && spaces.len() <= 3);

    // 3. One space.
    let space = client.space(&spaces[0].slug).expect("space");
    assert_eq!(space.slug, spaces[0].slug);
}
