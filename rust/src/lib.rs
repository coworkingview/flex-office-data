//! Client for [CoworkingView](https://coworkingview.com)'s public, keyless
//! API: the **CoworkingView Price Index** — what flexible office space costs,
//! city by city — and catalogue search over coworking spaces, private
//! offices, meeting rooms, event spaces and virtual offices.
//!
//! The same crate builds the `cwv` command-line tool (feature `cli`, on by
//! default). Library users who do not need it can depend on
//! `coworkingview = { version = "0.1", default-features = false }`.
//!
//! # Quick start
//!
//! ```no_run
//! use coworkingview::{Client, Product, RatesQuery, SpacesQuery};
//!
//! let client = Client::new();
//!
//! // Median monthly flex-desk price in every city of the index.
//! let rates = client.rates_with(&RatesQuery::new().product(Product::FlexDesk))?;
//! for r in rates.iter() {
//!     println!("{:<12} {:>6} {}/{}", r.city_name, r.median, r.currency, r.unit.unwrap());
//! }
//! // The index is CC BY 4.0: publish the attribution with the figures.
//! println!("{}", rates.attribution.as_deref().unwrap_or_default());
//!
//! // Up to 20 spaces in Berlin-Mitte with a private office.
//! let spaces = client.spaces(
//!     &SpacesQuery::new()
//!         .city("berlin")
//!         .zone("mitte")
//!         .product(Product::PrivateOffice)
//!         .limit(20),
//! )?;
//! for s in spaces.iter() {
//!     println!("{} — {}", s.title, s.url);
//! }
//! # Ok::<(), coworkingview::Error>(())
//! ```
//!
//! # What you get
//!
//! | Method | Endpoint | Rows |
//! |---|---|---|
//! | [`Client::rates`] | `GET /v1/market/rates` | [`RateRow`]: one per city × product |
//! | [`Client::cities`] | `GET /v1/market/rates` | [`CityRow`]: one per city |
//! | [`Client::spaces`] | `GET /v1/properties` | [`SpaceRow`]: one per space (max 200) |
//! | [`Client::space`] | `GET /v1/properties/{slug}` | [`Space`] with its [`PricingRow`]s |
//!
//! Every result is a [`Dataset`], which dereferences to the rows and carries
//! the attribution that must travel with them. [`csv::write`] writes any of
//! the row types in the kit's shared CSV format.
//!
//! # Licence of the data
//!
//! The Price Index is published under
//! [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/): reuse it freely
//! with attribution. Catalogue content (names, descriptions, prices of
//! individual spaces) belongs to the operators and is **not** licensed: you
//! may search it and link to the listings, not copy the catalogue. That is why
//! [`Client::spaces`] returns at most [`MAX_SPACES`] rows and no photos or
//! descriptions.
//!
//! # HTTP behaviour
//!
//! Requests are blocking (via [`ureq`](https://docs.rs/ureq) and rustls), time
//! out after 20 s, and are retried **once** on `429` or `5xx` after the
//! server's `Retry-After` (capped at 10 s). Set `COWORKINGVIEW_API_URL` to
//! point the client at another server. No network call happens until you call
//! a method.

#![deny(missing_docs)]
#![cfg_attr(docsrs, feature(doc_cfg))]

mod client;
pub mod csv;
mod error;
mod model;
pub mod parse;
mod types;

pub use client::{
    is_valid_slug, Client, ClientBuilder, RatesQuery, SpacesQuery, BASE_URL_ENV, DEFAULT_BASE_URL,
    DEFAULT_SPACES_LIMIT, MAX_SPACES, USER_AGENT,
};
pub use error::{ApiError, Error, FieldError, Result};
pub use model::{CityRow, Dataset, PricingRow, RateRow, Space, SpaceRow};
pub use types::{Currency, Locale, ParseValueError, Product, Sort, Unit};
