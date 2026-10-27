//! The blocking HTTP client.

use std::time::Duration;

use crate::error::{ApiError, Error, Result};
use crate::model::{CityRow, Dataset, RateRow, Space, SpaceRow};
use crate::parse;
use crate::types::{Currency, Locale, Product, Sort};

/// The production API.
pub const DEFAULT_BASE_URL: &str = "https://api.coworkingview.com";

/// Environment variable that overrides [`DEFAULT_BASE_URL`].
pub const BASE_URL_ENV: &str = "COWORKINGVIEW_API_URL";

/// Most spaces a single [`Client::spaces`] call returns. The catalogue may be
/// searched and linked, not bulk-copied.
pub const MAX_SPACES: usize = 200;

/// Spaces returned when [`SpacesQuery::limit`] is not set.
pub const DEFAULT_SPACES_LIMIT: usize = 50;

/// Largest page requested; smaller limits ask for exactly `limit` rows.
const MAX_PAGE_SIZE: usize = 50;
const TIMEOUT: Duration = Duration::from_secs(20);
const DEFAULT_RETRY_WAIT: Duration = Duration::from_secs(2);
const MAX_RETRY_WAIT: Duration = Duration::from_secs(10);

/// The `User-Agent` this crate sends.
pub const USER_AGENT: &str = concat!(
    "coworkingview-rust/",
    env!("CARGO_PKG_VERSION"),
    " (+https://github.com/coworkingview/flex-office-data)"
);

/// A client for the CoworkingView public API.
///
/// Cheap to clone; clones share a connection pool. Creating a client makes no
/// network calls.
///
/// ```no_run
/// use coworkingview::{Client, Product, RatesQuery};
///
/// let client = Client::new();
/// let berlin = client.rates_with(&RatesQuery::new().city("berlin").product(Product::FlexDesk))?;
/// println!("{} {}", berlin[0].median, berlin[0].currency);
/// # Ok::<(), coworkingview::Error>(())
/// ```
#[derive(Debug, Clone)]
pub struct Client {
    agent: ureq::Agent,
    base_url: String,
    locale: Locale,
}

impl Default for Client {
    fn default() -> Self {
        Client::new()
    }
}

impl Client {
    /// A client for [`DEFAULT_BASE_URL`], or for `$COWORKINGVIEW_API_URL` when
    /// set, with English names and links.
    pub fn new() -> Self {
        ClientBuilder::default().build()
    }

    /// Configures a client.
    pub fn builder() -> ClientBuilder {
        ClientBuilder::default()
    }

    /// The API base URL this client talks to.
    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    /// The default locale for requests that do not set one.
    pub fn locale(&self) -> Locale {
        self.locale
    }

    /// The whole Price Index: one row per city × product, in the client's
    /// locale and each city's own currency.
    pub fn rates(&self) -> Result<Dataset<Vec<RateRow>>> {
        self.rates_with(&RatesQuery::default())
    }

    /// The Price Index, filtered (`GET /v1/market/rates`).
    pub fn rates_with(&self, q: &RatesQuery) -> Result<Dataset<Vec<RateRow>>> {
        let body = self.get("/v1/market/rates", &self.rates_params(q))?;
        let mut ds = parse::rates(&body)?;
        if !q.products.is_empty() {
            ds.data.retain(|r| q.products.contains(&r.product));
        }
        Ok(ds)
    }

    /// Every city of the Price Index, published or not.
    pub fn cities(&self) -> Result<Dataset<Vec<CityRow>>> {
        self.cities_with(&RatesQuery::default())
    }

    /// Cities of the Price Index, filtered. [`RatesQuery::product`] is
    /// ignored.
    pub fn cities_with(&self, q: &RatesQuery) -> Result<Dataset<Vec<CityRow>>> {
        let body = self.get("/v1/market/rates", &self.rates_params(q))?;
        parse::cities(&body)
    }

    /// Searches the catalogue (`GET /v1/properties`, `pageSize = min(50, limit)`),
    /// following pages until
    /// [`SpacesQuery::limit`] rows (at most [`MAX_SPACES`]) or the last page.
    ///
    /// With random order (the default) the seed of the first page is reused
    /// on the following ones, so pages never overlap.
    pub fn spaces(&self, q: &SpacesQuery) -> Result<Dataset<Vec<SpaceRow>>> {
        let locale = q.locale.unwrap_or(self.locale);
        let limit = q.limit.unwrap_or(DEFAULT_SPACES_LIMIT).clamp(1, MAX_SPACES);
        let random = q.sort.unwrap_or_default() == Sort::Random;

        let mut base: Vec<(&str, String)> = vec![("locale", locale.to_string())];
        let mut push = |k: &'static str, v: Option<String>| {
            if let Some(v) = v {
                base.push((k, v));
            }
        };
        push("city", q.city.clone());
        push("country", q.country.clone());
        push("zone", q.zone.clone());
        push("operator", q.operator.clone());
        push(
            "pricingOptionType",
            q.product.as_ref().map(Product::to_string),
        );
        push("minCapacity", q.min_capacity.map(|v| v.to_string()));
        push("minPrice", q.min_price.map(crate::csv::num));
        push("maxPrice", q.max_price.map(crate::csv::num));
        push("currency", q.currency.as_ref().map(Currency::to_string));
        push("sortBy", q.sort.map(|s| s.to_string()));

        let mut seed = q.seed.map(|s| s.to_string());
        let mut rows: Vec<SpaceRow> = Vec::new();
        let mut first: Option<Dataset<()>> = None;
        let mut page = 1u64;
        loop {
            let mut params = base.clone();
            params.push(("page", page.to_string()));
            params.push(("pageSize", limit.min(MAX_PAGE_SIZE).to_string()));
            if let Some(s) = &seed {
                params.push(("seed", s.clone()));
            }
            let body = self.get("/v1/properties", &params)?;
            let p = parse::spaces_page(&body, locale)?;
            if page == 1 && random && seed.is_none() {
                seed = p.seed.as_ref().map(|s| match s {
                    serde_json::Value::String(s) => s.clone(),
                    other => other.to_string(),
                });
            }
            let got = p.dataset.data.len();
            let ds = p.dataset;
            rows.extend(ds.data.into_iter().take(limit - rows.len()));
            if first.is_none() {
                first = Some(Dataset {
                    attribution: ds.attribution,
                    license: ds.license,
                    as_of: ds.as_of,
                    notice: ds.notice,
                    data: (),
                });
            }
            let last = p.page_count.is_none_or(|n| page >= n);
            if rows.len() >= limit || got == 0 || last {
                break;
            }
            page += 1;
        }
        Ok(first.expect("at least one page").map(|()| rows))
    }

    /// One space with its pricing table (`GET /v1/properties/{slug}`), in the
    /// client's locale.
    pub fn space(&self, slug: &str) -> Result<Dataset<Space>> {
        self.space_in(slug, self.locale)
    }

    /// One space, in the given locale.
    pub fn space_in(&self, slug: &str, locale: Locale) -> Result<Dataset<Space>> {
        if !is_valid_slug(slug) {
            return Err(Error::InvalidSlug(slug.to_string()));
        }
        let path = format!("/v1/properties/{slug}");
        let body = self.get(&path, &[("locale", locale.to_string())])?;
        parse::space(&body, locale)
    }

    fn rates_params(&self, q: &RatesQuery) -> Vec<(&'static str, String)> {
        let mut p = vec![("locale", q.locale.unwrap_or(self.locale).to_string())];
        if let Some(v) = &q.city {
            p.push(("city", v.clone()));
        }
        if let Some(v) = &q.country {
            p.push(("country", v.clone()));
        }
        if let Some(v) = &q.currency {
            p.push(("currency", v.to_string()));
        }
        p
    }

    /// GET with the retry policy of SPEC §2. Returns the body of a 2xx.
    fn get(&self, path: &str, params: &[(&str, String)]) -> Result<String> {
        let url = format!("{}{}", self.base_url, path);
        let mut retried = false;
        loop {
            let resp = self
                .agent
                .get(&url)
                .header("Accept", "application/json")
                .query_pairs(params.iter().map(|(k, v)| (*k, v.as_str())))
                .call()
                .map_err(|e| Error::Network {
                    url: url.clone(),
                    source: Box::new(e),
                })?;
            let status = resp.status().as_u16();
            if (status == 429 || status >= 500) && !retried {
                retried = true;
                std::thread::sleep(retry_wait(
                    header(&resp, "retry-after").as_deref(),
                    header(&resp, "ratelimit-reset").as_deref(),
                ));
                continue;
            }
            let mut resp = resp;
            let body = resp.body_mut().read_to_string();
            if !(200..300).contains(&status) {
                return Err(ApiError::from_response(status, &body.unwrap_or_default()).into());
            }
            return body.map_err(|e| Error::bad(status, format!("unreadable body ({e})")));
        }
    }
}

fn header(resp: &ureq::http::Response<ureq::Body>, name: &str) -> Option<String> {
    resp.headers()
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned)
}

/// How long to wait before the single retry: `Retry-After` seconds, else
/// `RateLimit-Reset` seconds, else 2 s; never more than 10 s.
pub(crate) fn retry_wait(retry_after: Option<&str>, ratelimit_reset: Option<&str>) -> Duration {
    let secs = |v: Option<&str>| {
        v.and_then(|s| s.trim().parse::<f64>().ok())
            .filter(|s| s.is_finite() && *s >= 0.0)
            .map(Duration::from_secs_f64)
    };
    secs(retry_after)
        .or_else(|| secs(ratelimit_reset))
        .unwrap_or(DEFAULT_RETRY_WAIT)
        .min(MAX_RETRY_WAIT)
}

/// `^[A-Za-z0-9][A-Za-z0-9._-]*$` (SPEC §2): slugs go into a URL path.
pub fn is_valid_slug(slug: &str) -> bool {
    let mut bytes = slug.bytes();
    bytes.next().is_some_and(|b| b.is_ascii_alphanumeric())
        && bytes.all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

/// Configures a [`Client`].
#[derive(Debug, Clone, Default)]
pub struct ClientBuilder {
    base_url: Option<String>,
    locale: Locale,
    timeout: Option<Duration>,
}

impl ClientBuilder {
    /// API base URL. Defaults to `$COWORKINGVIEW_API_URL`, else
    /// [`DEFAULT_BASE_URL`].
    pub fn base_url(mut self, url: impl Into<String>) -> Self {
        self.base_url = Some(url.into());
        self
    }

    /// Default locale for names and links (default: English).
    pub fn locale(mut self, locale: Locale) -> Self {
        self.locale = locale;
        self
    }

    /// Overall timeout per request (default: 20 s).
    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    /// Builds the client. Makes no network calls.
    pub fn build(self) -> Client {
        let base_url = self
            .base_url
            .or_else(|| {
                std::env::var(BASE_URL_ENV)
                    .ok()
                    .filter(|s| !s.trim().is_empty())
            })
            .unwrap_or_else(|| DEFAULT_BASE_URL.to_string());
        let config = ureq::Agent::config_builder()
            .timeout_global(Some(self.timeout.unwrap_or(TIMEOUT)))
            .http_status_as_error(false)
            .user_agent(USER_AGENT)
            .build();
        Client {
            agent: config.into(),
            base_url: base_url.trim().trim_end_matches('/').to_string(),
            locale: self.locale,
        }
    }
}

/// Filters for [`Client::rates_with`] and [`Client::cities_with`].
#[derive(Debug, Clone, Default, PartialEq)]
#[non_exhaustive]
pub struct RatesQuery {
    /// City slug, e.g. `"berlin"`.
    pub city: Option<String>,
    /// ISO 3166-1 alpha-2 country code, e.g. `"DE"`.
    pub country: Option<String>,
    /// Currency to present the figures in (default: each city's own).
    pub currency: Option<Currency>,
    /// Locale for city names (default: the client's).
    pub locale: Option<Locale>,
    /// Keep only these products (default: all). Applied locally.
    pub products: Vec<Product>,
}

impl RatesQuery {
    /// An unfiltered query.
    pub fn new() -> Self {
        Self::default()
    }
    /// Only this city (slug).
    pub fn city(mut self, slug: impl Into<String>) -> Self {
        self.city = Some(slug.into());
        self
    }
    /// Only this country (ISO 3166-1 alpha-2).
    pub fn country(mut self, code: impl Into<String>) -> Self {
        self.country = Some(code.into());
        self
    }
    /// Present figures in this currency.
    pub fn currency(mut self, currency: Currency) -> Self {
        self.currency = Some(currency);
        self
    }
    /// Names in this locale.
    pub fn locale(mut self, locale: Locale) -> Self {
        self.locale = Some(locale);
        self
    }
    /// Keep this product (call repeatedly to keep several).
    pub fn product(mut self, product: Product) -> Self {
        self.products.push(product);
        self
    }
}

/// Filters for [`Client::spaces`].
#[derive(Debug, Clone, Default, PartialEq)]
#[non_exhaustive]
pub struct SpacesQuery {
    /// City slug, e.g. `"berlin"`.
    pub city: Option<String>,
    /// ISO 3166-1 alpha-2 country code.
    pub country: Option<String>,
    /// Zone (district) slug, e.g. `"mitte"`.
    pub zone: Option<String>,
    /// Operator slug, e.g. `"regus"`.
    pub operator: Option<String>,
    /// Only spaces offering this product.
    pub product: Option<Product>,
    /// Only spaces with an offer for at least this many people.
    pub min_capacity: Option<u32>,
    /// Lowest price (in `currency`).
    pub min_price: Option<f64>,
    /// Highest price (in `currency`).
    pub max_price: Option<f64>,
    /// Currency of the price filters.
    pub currency: Option<Currency>,
    /// Result order (default: random).
    pub sort: Option<Sort>,
    /// Seed for random order, to get the same order again.
    pub seed: Option<u64>,
    /// Locale of the links (default: the client's).
    pub locale: Option<Locale>,
    /// Most rows to return (default 50, capped at [`MAX_SPACES`]).
    pub limit: Option<usize>,
}

impl SpacesQuery {
    /// An unfiltered query (50 random spaces).
    pub fn new() -> Self {
        Self::default()
    }
    /// Only this city (slug).
    pub fn city(mut self, slug: impl Into<String>) -> Self {
        self.city = Some(slug.into());
        self
    }
    /// Only this country (ISO 3166-1 alpha-2).
    pub fn country(mut self, code: impl Into<String>) -> Self {
        self.country = Some(code.into());
        self
    }
    /// Only this zone (slug).
    pub fn zone(mut self, slug: impl Into<String>) -> Self {
        self.zone = Some(slug.into());
        self
    }
    /// Only this operator (slug).
    pub fn operator(mut self, slug: impl Into<String>) -> Self {
        self.operator = Some(slug.into());
        self
    }
    /// Only spaces offering this product.
    pub fn product(mut self, product: Product) -> Self {
        self.product = Some(product);
        self
    }
    /// Only spaces fitting at least this many people.
    pub fn min_capacity(mut self, people: u32) -> Self {
        self.min_capacity = Some(people);
        self
    }
    /// Lowest price.
    pub fn min_price(mut self, price: f64) -> Self {
        self.min_price = Some(price);
        self
    }
    /// Highest price.
    pub fn max_price(mut self, price: f64) -> Self {
        self.max_price = Some(price);
        self
    }
    /// Currency of the price filters.
    pub fn currency(mut self, currency: Currency) -> Self {
        self.currency = Some(currency);
        self
    }
    /// Result order.
    pub fn sort(mut self, sort: Sort) -> Self {
        self.sort = Some(sort);
        self
    }
    /// Seed for random order.
    pub fn seed(mut self, seed: u64) -> Self {
        self.seed = Some(seed);
        self
    }
    /// Locale of the links.
    pub fn locale(mut self, locale: Locale) -> Self {
        self.locale = Some(locale);
        self
    }
    /// Most rows to return (capped at [`MAX_SPACES`]).
    pub fn limit(mut self, limit: usize) -> Self {
        self.limit = Some(limit);
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retry_wait_policy() {
        assert_eq!(retry_wait(Some("3"), Some("7")), Duration::from_secs(3));
        assert_eq!(retry_wait(None, Some("7")), Duration::from_secs(7));
        assert_eq!(retry_wait(Some("soon"), None), Duration::from_secs(2));
        assert_eq!(retry_wait(None, None), Duration::from_secs(2));
        assert_eq!(retry_wait(Some("120"), None), Duration::from_secs(10));
        assert_eq!(retry_wait(None, Some("3600")), Duration::from_secs(10));
    }

    #[test]
    fn user_agent() {
        assert_eq!(
            USER_AGENT,
            format!(
                "coworkingview-rust/{} (+https://github.com/coworkingview/flex-office-data)",
                env!("CARGO_PKG_VERSION")
            )
        );
    }

    #[test]
    fn slug_validation() {
        assert!(is_valid_slug("sankt-oberholz-rosenthaler-berlin"));
        assert!(is_valid_slug("a.b_c-1"));
        assert!(!is_valid_slug(""));
        assert!(!is_valid_slug("-leading"));
        assert!(!is_valid_slug("../etc"));
        assert!(!is_valid_slug("a b"));
        assert!(!is_valid_slug("a/b"));
        assert!(!is_valid_slug("café"));
    }
}
