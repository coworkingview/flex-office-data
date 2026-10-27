//! End-to-end tests of the `cwv` binary against a local mock server.
//! Nothing here touches the network beyond 127.0.0.1.

mod common;

use assert_cmd::Command;
use common::{fixture, golden, spaces_page, MockServer, Reply};
use predicates::prelude::*;

fn cwv(server: &MockServer) -> Command {
    let mut cmd = Command::cargo_bin("cwv").unwrap();
    cmd.env("COWORKINGVIEW_API_URL", &server.url)
        .env_remove("NO_COLOR")
        .env_remove("CWV_LOCALE");
    cmd
}

fn offline() -> Command {
    let mut cmd = Command::cargo_bin("cwv").unwrap();
    // Port 9 (discard) on localhost: any accidental request fails fast.
    cmd.env("COWORKINGVIEW_API_URL", "http://127.0.0.1:9");
    cmd
}

const ATTRIBUTION: &str = "Source: CoworkingView Price Index";

// --- rates / cities ---------------------------------------------------------

#[test]
fn rates_csv_matches_golden_and_attribution_goes_to_stderr() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    let out = cwv(&server)
        .args(["rates", "--format", "csv"])
        .assert()
        .success();
    let out = out.get_output();
    assert_eq!(String::from_utf8_lossy(&out.stdout), golden("rates.csv"));
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains(ATTRIBUTION), "stderr: {stderr}");

    let reqs = server.requests();
    assert_eq!(reqs.len(), 1);
    assert_eq!(reqs[0].path(), "/v1/market/rates");
    assert_eq!(reqs[0].query("locale").as_deref(), Some("en"));
    assert_eq!(
        reqs[0].header("user-agent"),
        Some(concat!(
            "coworkingview-rust/",
            env!("CARGO_PKG_VERSION"),
            " (+https://github.com/coworkingview/flex-office-data)"
        ))
    );
    assert_eq!(reqs[0].header("accept"), Some("application/json"));
}

#[test]
fn rates_filters_are_sent_and_products_filtered_locally() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    let out = cwv(&server)
        .args([
            "rates",
            "--city",
            "berlin",
            "--country",
            "DE",
            "--currency",
            "usd",
            "--locale",
            "de",
            "-p",
            "day_pass,flex_desk",
            "-f",
            "csv",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8_lossy(&out.get_output().stdout).into_owned();
    let products: Vec<_> = stdout
        .lines()
        .skip(1)
        .map(|l| l.split(',').nth(4).unwrap().to_owned())
        .collect();
    assert!(products.iter().all(|p| p == "flex_desk" || p == "day_pass"));
    assert_eq!(products.len(), 5, "{stdout}");
    let r = &server.requests()[0];
    assert_eq!(r.query("city").as_deref(), Some("berlin"));
    assert_eq!(r.query("country").as_deref(), Some("DE"));
    assert_eq!(r.query("currency").as_deref(), Some("USD"));
    assert_eq!(r.query("locale").as_deref(), Some("de"));
}

#[test]
fn rates_json_is_wrapped_with_attribution() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    let out = cwv(&server)
        .args(["rates", "--format", "json"])
        .assert()
        .success();
    let out = out.get_output();
    assert!(out.stderr.is_empty(), "nothing on stderr for JSON");
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    assert!(v["attribution"].as_str().unwrap().starts_with(ATTRIBUTION));
    assert_eq!(v["license"], "https://creativecommons.org/licenses/by/4.0/");
    assert_eq!(v["as_of"], "2026-10-27T21:06:48.313Z");
    let rows = v["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 13);
    assert_eq!(rows[0]["city_slug"], "abu-dhabi");
    assert_eq!(rows[0]["product"], "flex_desk");
    assert_eq!(rows[0]["unit"], "month");
    assert_eq!(rows[0]["low_confidence"], true);
    assert_eq!(rows[6]["p25"], serde_json::Value::Null);
}

#[test]
fn rates_table_shows_money_with_currency() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    cwv(&server)
        .args(["rates", "--no-color"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Berlin"))
        .stdout(predicate::str::contains("214 EUR"))
        .stdout(predicate::str::contains("1,400 AED"))
        .stdout(predicate::str::contains("\x1b[").not())
        .stderr(predicate::str::contains("fewer than 10 prices"))
        .stderr(predicate::str::contains(ATTRIBUTION));
}

#[test]
fn cities_csv_matches_golden() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    let out = cwv(&server)
        .args(["cities", "-f", "csv"])
        .assert()
        .success();
    let out = out.get_output();
    assert_eq!(String::from_utf8_lossy(&out.stdout), golden("cities.csv"));
    assert!(String::from_utf8_lossy(&out.stderr).contains(ATTRIBUTION));
}

#[test]
fn cities_table_lists_unpublished() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    cwv(&server)
        .arg("cities")
        .assert()
        .success()
        .stdout(predicate::str::contains("Example Town"))
        .stdout(predicate::str::contains("not published yet"))
        .stdout(predicate::str::contains("80 – 2,100 EUR"));
}

// --- HTTP behaviour -----------------------------------------------------------

#[test]
fn retries_once_after_503() {
    let server = MockServer::start(vec![
        Reply::json(
            503,
            r#"{"title":"Unavailable","status":503,"code":"UNAVAILABLE"}"#,
        )
        .header("Retry-After", "0"),
        Reply::ok(fixture("market_rates.json")),
    ]);
    cwv(&server).args(["rates", "-f", "csv"]).assert().success();
    assert_eq!(server.requests().len(), 2);
}

#[test]
fn retries_once_after_429_using_ratelimit_reset() {
    let server = MockServer::start(vec![
        Reply::json(
            429,
            r#"{"title":"Too many requests","status":429,"code":"RATE_LIMITED"}"#,
        )
        .header("RateLimit-Reset", "0"),
        Reply::ok(fixture("market_rates.json")),
    ]);
    cwv(&server)
        .args(["cities", "-f", "csv"])
        .assert()
        .success();
    assert_eq!(server.requests().len(), 2);
}

#[test]
fn never_retries_more_than_once() {
    let fail = Reply::json(
        502,
        r#"{"title":"Bad gateway","status":502,"code":"UPSTREAM_DOWN"}"#,
    )
    .header("Retry-After", "0");
    let server = MockServer::start(vec![fail.clone(), fail.clone(), fail]);
    cwv(&server)
        .args(["rates"])
        .assert()
        .code(1)
        .stdout("")
        .stderr(predicate::str::contains("UPSTREAM_DOWN"))
        .stderr(predicate::str::contains("HTTP 502"));
    assert_eq!(server.requests().len(), 2);
}

#[test]
fn does_not_retry_4xx() {
    let server = MockServer::start(vec![Reply::json(400, fixture("error_validation.json"))]);
    cwv(&server)
        .args(["rates", "--currency", "VES"])
        .assert()
        .code(1)
        .stderr(predicate::str::contains("Validation failed"))
        .stderr(predicate::str::contains("VALIDATION_FAILED"))
        .stderr(predicate::str::contains("no approximate rate"))
        .stderr(predicate::str::contains("currency:"));
    let reqs = server.requests();
    assert_eq!(reqs.len(), 1);
    assert_eq!(reqs[0].query("currency").as_deref(), Some("VES"));
}

#[test]
fn non_problem_error_body_falls_back_to_reason() {
    let server = MockServer::start(vec![Reply {
        status: 404,
        headers: vec![("Content-Type".into(), "text/html".into())],
        body: "<h1>nope</h1>".into(),
    }]);
    cwv(&server)
        .args(["space", "does-not-exist"])
        .assert()
        .code(1)
        .stderr(predicate::str::contains("Not Found"))
        .stderr(predicate::str::contains("HTTP_404"));
}

#[test]
fn non_json_success_is_bad_response() {
    let server = MockServer::start(vec![Reply {
        status: 200,
        headers: vec![("Content-Type".into(), "text/html".into())],
        body: "<html>maintenance</html>".into(),
    }]);
    cwv(&server)
        .args(["rates"])
        .assert()
        .code(1)
        .stderr(predicate::str::contains("unexpected response"));
}

#[test]
fn network_error_exits_1() {
    offline()
        .args(["cities"])
        .assert()
        .code(1)
        .stderr(predicate::str::contains("could not reach"));
}

// --- spaces -------------------------------------------------------------------

#[test]
fn spaces_follows_pages_up_to_limit_and_reuses_seed() {
    let server = MockServer::start(vec![
        Reply::ok(spaces_page(1, 50, 37, 2085917097)),
        Reply::ok(spaces_page(2, 50, 37, 999)),
        Reply::ok(spaces_page(3, 50, 37, 999)),
    ]);
    let out = cwv(&server)
        .args(["spaces", "--city", "berlin", "--limit", "120", "-f", "json"])
        .assert()
        .success();
    let v: serde_json::Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(v["rows"].as_array().unwrap().len(), 120);
    assert!(v["attribution"]
        .as_str()
        .unwrap()
        .contains("Coworking spaces in Berlin"));
    assert!(v["notice"]
        .as_str()
        .unwrap()
        .contains("Systematic extraction"));

    let reqs = server.requests();
    assert_eq!(reqs.len(), 3);
    for (i, r) in reqs.iter().enumerate() {
        assert_eq!(r.path(), "/v1/properties");
        assert_eq!(r.query("page"), Some((i + 1).to_string()));
        assert_eq!(r.query("pageSize").as_deref(), Some("50"));
        assert_eq!(r.query("city").as_deref(), Some("berlin"));
    }
    assert_eq!(reqs[0].query("seed"), None, "page 1 asks for a fresh seed");
    assert_eq!(reqs[1].query("seed").as_deref(), Some("2085917097"));
    assert_eq!(reqs[2].query("seed").as_deref(), Some("2085917097"));
}

#[test]
fn spaces_stops_at_last_page() {
    let server = MockServer::start(vec![
        Reply::ok(spaces_page(1, 50, 2, 7)),
        Reply::ok(spaces_page(2, 12, 2, 7)),
    ]);
    let out = cwv(&server)
        .args(["spaces", "--limit", "200", "-f", "csv"])
        .assert()
        .success();
    let stdout = String::from_utf8_lossy(&out.get_output().stdout).into_owned();
    assert_eq!(stdout.lines().count(), 1 + 62);
    assert_eq!(server.requests().len(), 2);
}

#[test]
fn spaces_limit_200_fetches_at_most_four_pages() {
    let pages: Vec<_> = (1..=6)
        .map(|p| Reply::ok(spaces_page(p, 50, 37, 1)))
        .collect();
    let server = MockServer::start(pages);
    let out = cwv(&server)
        .args(["spaces", "--limit", "200", "-f", "csv"])
        .assert()
        .success();
    let stdout = String::from_utf8_lossy(&out.get_output().stdout).into_owned();
    assert_eq!(stdout.lines().count(), 1 + 200);
    assert_eq!(server.requests().len(), 4);
}

#[test]
fn spaces_limit_above_200_is_a_usage_error() {
    offline()
        .args(["spaces", "--limit", "201"])
        .assert()
        .code(2)
        .stderr(predicate::str::contains("201"));
}

#[test]
fn spaces_sends_filters_and_no_seed_for_explicit_sort() {
    let server = MockServer::start(vec![
        Reply::ok(spaces_page(1, 50, 3, 5)),
        Reply::ok(spaces_page(2, 50, 3, 5)),
    ]);
    cwv(&server)
        .args([
            "spaces",
            "--city",
            "madrid",
            "--zone",
            "salamanca",
            "--operator",
            "regus",
            "--product",
            "private_office",
            "--min-capacity",
            "4",
            "--min-price",
            "100",
            "--max-price",
            "999.5",
            "--currency",
            "eur",
            "--sort",
            "price-asc",
            "--limit",
            "60",
            "--locale",
            "es",
            "-f",
            "csv",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "https://coworkingview.com/es/oficina/space-p1-0",
        ));
    let reqs = server.requests();
    assert_eq!(reqs.len(), 2);
    let r = &reqs[0];
    for (k, v) in [
        ("city", "madrid"),
        ("zone", "salamanca"),
        ("operator", "regus"),
        ("pricingOptionType", "private_office"),
        ("minCapacity", "4"),
        ("minPrice", "100"),
        ("maxPrice", "999.5"),
        ("currency", "EUR"),
        ("sortBy", "price-asc"),
        ("locale", "es"),
    ] {
        assert_eq!(r.query(k).as_deref(), Some(v), "{k}");
    }
    assert_eq!(reqs[1].query("seed"), None);
}

#[test]
fn spaces_explicit_seed_is_sent_on_every_page() {
    let server = MockServer::start(vec![
        Reply::ok(spaces_page(1, 50, 2, 42)),
        Reply::ok(spaces_page(2, 50, 2, 42)),
    ]);
    cwv(&server)
        .args(["spaces", "--seed", "42", "--limit", "100", "-f", "csv"])
        .assert()
        .success();
    let reqs = server.requests();
    assert!(reqs
        .iter()
        .all(|r| r.query("seed").as_deref() == Some("42")));
}

#[test]
fn spaces_table_and_empty_result() {
    let server = MockServer::start(vec![Reply::ok(spaces_page(1, 2, 1, 3))]);
    cwv(&server)
        .args(["spaces"])
        .assert()
        .success()
        .stdout(predicate::str::contains("space-p1-1"))
        .stderr(predicate::str::contains("2 spaces"))
        .stderr(predicate::str::contains("Systematic extraction"));

    let server = MockServer::start(vec![Reply::ok(fixture("properties_empty.json"))]);
    cwv(&server)
        .args(["spaces", "--city", "nowhere-xyz"])
        .assert()
        .success()
        .stdout("")
        .stderr(predicate::str::contains("No spaces match"));
}

// --- space ----------------------------------------------------------------------

#[test]
fn space_csv_is_the_pricing_table() {
    let server = MockServer::start(vec![Reply::ok(fixture("property_detail.json"))]);
    let out = cwv(&server)
        .args(["space", "sankt-oberholz-rosenthaler-berlin", "-f", "csv"])
        .assert()
        .success();
    let out = out.get_output();
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        golden("space_pricing.csv")
    );
    let reqs = server.requests();
    assert_eq!(
        reqs[0].path(),
        "/v1/properties/sankt-oberholz-rosenthaler-berlin"
    );
}

#[test]
fn space_json_and_table() {
    let server = MockServer::start(vec![Reply::ok(fixture("property_detail.json"))]);
    let out = cwv(&server)
        .args(["space", "sankt-oberholz-rosenthaler-berlin", "-f", "json"])
        .assert()
        .success();
    let v: serde_json::Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(v["space"]["slug"], "sankt-oberholz-rosenthaler-berlin");
    assert!(v["space"].get("pricing").is_none());
    assert_eq!(v["rows"].as_array().unwrap().len(), 5);
    assert_eq!(v["rows"][1]["price"], serde_json::Value::Null);

    let server = MockServer::start(vec![Reply::ok(fixture("property_detail.json"))]);
    cwv(&server)
        .args(["space", "sankt-oberholz-rosenthaler-berlin"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Rosenthaler Straße 72a"))
        .stdout(predicate::str::contains("209 EUR"))
        .stdout(predicate::str::contains("on request"))
        .stdout(predicate::str::contains(
            "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
        ));
}

// --- usage, help, completions ------------------------------------------------------

#[test]
fn usage_errors_exit_2() {
    offline()
        .args(["rates", "--product", "desk"])
        .assert()
        .code(2);
    offline()
        .args(["rates", "--currency", "euro"])
        .assert()
        .code(2);
    offline()
        .args(["spaces", "--sort", "cheapest"])
        .assert()
        .code(2);
    offline().args(["frobnicate"]).assert().code(2);
    offline().assert().code(2);
}

#[test]
fn help_and_version() {
    offline()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("Examples:"))
        .stdout(predicate::str::contains("cwv rates --city berlin"));
    offline()
        .arg("--version")
        .assert()
        .success()
        .stdout(format!("cwv {}\n", env!("CARGO_PKG_VERSION")));
    offline()
        .args(["spaces", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("at most 200"));
}

#[test]
fn completions_and_man_page() {
    for shell in ["bash", "zsh", "fish", "powershell", "elvish"] {
        offline()
            .args(["completions", shell])
            .assert()
            .success()
            .stdout(predicate::str::contains("cwv"));
    }
    offline()
        .arg("man")
        .assert()
        .success()
        .stdout(predicate::str::contains(".TH cwv"));
}

// --- SPEC updates: pageSize, slugs, licence footer ----------------------------

#[test]
fn small_limit_asks_for_exactly_that_page_size() {
    let server = MockServer::start(vec![Reply::ok(spaces_page(1, 5, 30, 9))]);
    let out = cwv(&server)
        .args(["spaces", "--city", "berlin", "--limit", "5", "-f", "csv"])
        .assert()
        .success();
    let stdout = String::from_utf8_lossy(&out.get_output().stdout).into_owned();
    assert_eq!(stdout.lines().count(), 1 + 5);
    let reqs = server.requests();
    assert_eq!(reqs.len(), 1);
    assert_eq!(reqs[0].query("pageSize").as_deref(), Some("5"));
}

#[test]
fn invalid_slug_is_rejected_before_any_request() {
    for slug in ["../etc/passwd", "a b", "-x", "a/b", "caf\u{e9}"] {
        offline().args(["space", slug]).assert().code(2);
    }
}

#[test]
fn library_rejects_invalid_slug_without_network() {
    let client = coworkingview::Client::builder()
        .base_url("http://127.0.0.1:9")
        .build();
    let err = client.space("../v1/market/rates").unwrap_err();
    assert_eq!(err.code(), "INVALID_SLUG");
    let err = client.space("valid-slug").unwrap_err();
    assert_eq!(err.code(), "NETWORK_ERROR");
}

#[test]
fn licence_url_and_as_of_follow_the_attribution_on_stderr() {
    let server = MockServer::start(vec![Reply::ok(fixture("market_rates.json"))]);
    cwv(&server)
        .args(["rates", "-f", "csv"])
        .assert()
        .success()
        .stdout(predicate::str::contains("License:").not())
        .stderr(predicate::str::contains(
            "License: https://creativecommons.org/licenses/by/4.0/ (as of 2026-10-27T21:06:48.313Z)",
        ));
}
