//! Small value types used in queries and rows: [`Product`], [`Unit`],
//! [`Locale`], [`Currency`] and [`Sort`].
//!
//! Every type parses from and prints as the API's own spelling, so
//! `"flex_desk".parse::<Product>()` and `Product::FlexDesk.to_string()`
//! round-trip.

use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Error returned when a string is not a valid value for one of this crate's
/// enums (for example `"desk".parse::<Product>()`).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("invalid {kind} {value:?} (expected one of: {})", expected.join(", "))]
pub struct ParseValueError {
    /// What was being parsed, e.g. `"product"`.
    pub kind: &'static str,
    /// The rejected input.
    pub value: String,
    /// The accepted spellings.
    pub expected: &'static [&'static str],
}

macro_rules! serde_via_str {
    ($ty:ty) => {
        impl Serialize for $ty {
            fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
                s.collect_str(self)
            }
        }
    };
}

// ---------------------------------------------------------------------------
// Product
// ---------------------------------------------------------------------------

/// A kind of flexible-office product (the API's `pricingOptionType` /
/// `optionType`).
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[non_exhaustive]
pub enum Product {
    /// A hot desk in a shared area, billed monthly.
    FlexDesk,
    /// A dedicated (fixed) desk, billed monthly.
    FixDesk,
    /// A lockable private office, billed monthly.
    PrivateOffice,
    /// An exclusive area (`exclusive_bereich`), billed monthly.
    ExclusiveBereich,
    /// A day pass, billed per day.
    DayPass,
    /// A meeting room, billed per hour.
    MeetingRoom,
    /// An event space, billed per hour.
    EventSpace,
    /// A virtual office (business address), billed monthly.
    VirtualOffice,
    /// A membership.
    Membership,
    /// A product this version of the crate does not know yet, as reported by
    /// the API. New aggregates appear here without a release.
    Other(String),
}

impl Product {
    /// Every product this version knows, in the Price Index's display order.
    pub const ALL: [Product; 9] = [
        Product::FlexDesk,
        Product::FixDesk,
        Product::PrivateOffice,
        Product::ExclusiveBereich,
        Product::DayPass,
        Product::MeetingRoom,
        Product::EventSpace,
        Product::VirtualOffice,
        Product::Membership,
    ];

    /// The accepted spellings, in display order.
    pub const NAMES: &'static [&'static str] = &[
        "flex_desk",
        "fix_desk",
        "private_office",
        "exclusive_bereich",
        "day_pass",
        "meeting_room",
        "event_space",
        "virtual_office",
        "membership",
    ];

    /// The API spelling, e.g. `"flex_desk"`.
    pub fn as_str(&self) -> &str {
        match self {
            Product::FlexDesk => "flex_desk",
            Product::FixDesk => "fix_desk",
            Product::PrivateOffice => "private_office",
            Product::ExclusiveBereich => "exclusive_bereich",
            Product::DayPass => "day_pass",
            Product::MeetingRoom => "meeting_room",
            Product::EventSpace => "event_space",
            Product::VirtualOffice => "virtual_office",
            Product::Membership => "membership",
            Product::Other(s) => s,
        }
    }

    /// A short human label, e.g. `"Flex desk"`.
    pub fn label(&self) -> String {
        match self {
            Product::FlexDesk => "Flex desk".into(),
            Product::FixDesk => "Fixed desk".into(),
            Product::PrivateOffice => "Private office".into(),
            Product::ExclusiveBereich => "Exclusive area".into(),
            Product::DayPass => "Day pass".into(),
            Product::MeetingRoom => "Meeting room".into(),
            Product::EventSpace => "Event space".into(),
            Product::VirtualOffice => "Virtual office".into(),
            Product::Membership => "Membership".into(),
            Product::Other(s) => {
                let s = s.replace('_', " ");
                let mut c = s.chars();
                match c.next() {
                    Some(f) => f.to_uppercase().chain(c).collect(),
                    None => s,
                }
            }
        }
    }

    /// Reads a product name coming from the API: known names map to their
    /// variant, anything else becomes [`Product::Other`]. Never fails.
    pub fn from_api(s: &str) -> Product {
        s.parse().unwrap_or_else(|_| Product::Other(s.to_string()))
    }

    /// Position in the Price Index's product order (unknown products sort
    /// after all known ones, alphabetically).
    pub(crate) fn sort_key(&self) -> (u8, usize, &str) {
        match Product::NAMES.iter().position(|n| *n == self.as_str()) {
            Some(i) if !matches!(self, Product::Other(_)) => (0, i, ""),
            _ => (1, 0, self.as_str()),
        }
    }
}

impl fmt::Display for Product {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Product {
    type Err = ParseValueError;

    /// Parses a known product. Case-insensitive; `-` is accepted for `_`
    /// (`flex-desk`). Unknown names are an error; use [`Product::from_api`]
    /// to accept them.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let norm = s.trim().to_ascii_lowercase().replace('-', "_");
        Product::ALL
            .iter()
            .find(|p| p.as_str() == norm)
            .cloned()
            .ok_or_else(|| ParseValueError {
                kind: "product",
                value: s.to_string(),
                expected: Product::NAMES,
            })
    }
}

serde_via_str!(Product);

impl<'de> Deserialize<'de> for Product {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(Product::from_api(&s))
    }
}

// ---------------------------------------------------------------------------
// Unit
// ---------------------------------------------------------------------------

/// The billing unit a price refers to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum Unit {
    /// Per month.
    Month,
    /// Per day.
    Day,
    /// Per hour.
    Hour,
}

impl Unit {
    const NAMES: &'static [&'static str] = &["month", "day", "hour"];

    /// The spelling used in rows: `"month"`, `"day"` or `"hour"`.
    pub fn as_str(self) -> &'static str {
        match self {
            Unit::Month => "month",
            Unit::Day => "day",
            Unit::Hour => "hour",
        }
    }

    /// The unit of a non-monthly aggregate (SPEC §3): `day_pass` → day,
    /// `meeting_room`/`event_space` → hour, `virtual_office` → month.
    pub(crate) fn for_stat(product: &Product) -> Option<Unit> {
        match product {
            Product::DayPass => Some(Unit::Day),
            Product::MeetingRoom | Product::EventSpace => Some(Unit::Hour),
            Product::VirtualOffice => Some(Unit::Month),
            _ => None,
        }
    }
}

impl fmt::Display for Unit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Unit {
    type Err = ParseValueError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim().to_ascii_lowercase().as_str() {
            "month" => Ok(Unit::Month),
            "day" => Ok(Unit::Day),
            "hour" => Ok(Unit::Hour),
            _ => Err(ParseValueError {
                kind: "unit",
                value: s.to_string(),
                expected: Unit::NAMES,
            }),
        }
    }
}

serde_via_str!(Unit);

// ---------------------------------------------------------------------------
// Locale
// ---------------------------------------------------------------------------

/// Language of names and of the `coworkingview.com` links in results.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
#[non_exhaustive]
pub enum Locale {
    /// English (default). Links look like `/en/workspace/<slug>`.
    #[default]
    En,
    /// Spanish. Links look like `/es/oficina/<slug>`.
    Es,
    /// German. Links look like `/de/buero/<slug>`.
    De,
}

impl Locale {
    /// The accepted spellings.
    pub const NAMES: &'static [&'static str] = &["en", "es", "de"];

    /// The API spelling: `"en"`, `"es"` or `"de"`.
    pub fn as_str(self) -> &'static str {
        match self {
            Locale::En => "en",
            Locale::Es => "es",
            Locale::De => "de",
        }
    }

    /// The path segment for a space page on coworkingview.com.
    pub(crate) fn workspace_path(self) -> &'static str {
        match self {
            Locale::En => "workspace",
            Locale::Es => "oficina",
            Locale::De => "buero",
        }
    }
}

impl fmt::Display for Locale {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Locale {
    type Err = ParseValueError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim().to_ascii_lowercase().as_str() {
            "en" => Ok(Locale::En),
            "es" => Ok(Locale::Es),
            "de" => Ok(Locale::De),
            _ => Err(ParseValueError {
                kind: "locale",
                value: s.to_string(),
                expected: Locale::NAMES,
            }),
        }
    }
}

serde_via_str!(Locale);

// ---------------------------------------------------------------------------
// Currency
// ---------------------------------------------------------------------------

/// Currency to present prices in. The API converts from each city's own
/// currency using approximate rates.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum Currency {
    /// Euro.
    Eur,
    /// Pound sterling.
    Gbp,
    /// US dollar.
    Usd,
    /// Swiss franc.
    Chf,
    /// UAE dirham.
    Aed,
    /// Any other ISO 4217 code (for example `VES`). It is passed through
    /// unchanged and the API decides whether it can convert to it.
    Other(String),
}

impl Currency {
    /// The currencies the API documents.
    pub const NAMES: &'static [&'static str] = &["EUR", "GBP", "USD", "CHF", "AED"];

    /// The ISO 4217 code, e.g. `"EUR"`.
    pub fn as_str(&self) -> &str {
        match self {
            Currency::Eur => "EUR",
            Currency::Gbp => "GBP",
            Currency::Usd => "USD",
            Currency::Chf => "CHF",
            Currency::Aed => "AED",
            Currency::Other(s) => s,
        }
    }
}

impl fmt::Display for Currency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Currency {
    type Err = ParseValueError;

    /// Accepts any three-letter code, case-insensitively.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let code = s.trim().to_ascii_uppercase();
        if code.len() != 3 || !code.bytes().all(|b| b.is_ascii_uppercase()) {
            return Err(ParseValueError {
                kind: "currency",
                value: s.to_string(),
                expected: Currency::NAMES,
            });
        }
        Ok(match code.as_str() {
            "EUR" => Currency::Eur,
            "GBP" => Currency::Gbp,
            "USD" => Currency::Usd,
            "CHF" => Currency::Chf,
            "AED" => Currency::Aed,
            _ => Currency::Other(code),
        })
    }
}

serde_via_str!(Currency);

// ---------------------------------------------------------------------------
// Sort
// ---------------------------------------------------------------------------

/// Order of catalogue search results.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
#[non_exhaustive]
pub enum Sort {
    /// Seeded random order (default). Paging reuses the seed, so pages never
    /// overlap.
    #[default]
    Random,
    /// Cheapest first.
    PriceAsc,
    /// Most recently updated first.
    DateDesc,
    /// Least recently updated first.
    DateAsc,
}

impl Sort {
    /// The accepted spellings.
    pub const NAMES: &'static [&'static str] = &["random", "price-asc", "date-desc", "date-asc"];

    /// The API spelling, e.g. `"price-asc"`.
    pub fn as_str(self) -> &'static str {
        match self {
            Sort::Random => "random",
            Sort::PriceAsc => "price-asc",
            Sort::DateDesc => "date-desc",
            Sort::DateAsc => "date-asc",
        }
    }
}

impl fmt::Display for Sort {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Sort {
    type Err = ParseValueError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim().to_ascii_lowercase().replace('_', "-").as_str() {
            "random" => Ok(Sort::Random),
            "price-asc" => Ok(Sort::PriceAsc),
            "date-desc" => Ok(Sort::DateDesc),
            "date-asc" => Ok(Sort::DateAsc),
            _ => Err(ParseValueError {
                kind: "sort",
                value: s.to_string(),
                expected: Sort::NAMES,
            }),
        }
    }
}

serde_via_str!(Sort);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn product_round_trip() {
        for p in Product::ALL {
            assert_eq!(p.to_string().parse::<Product>().unwrap(), p);
        }
        assert_eq!("Flex-Desk".parse::<Product>().unwrap(), Product::FlexDesk);
        assert!("desk".parse::<Product>().is_err());
        assert_eq!(
            Product::from_api("event_space"),
            Product::EventSpace,
            "known names map to their variant"
        );
        assert_eq!(
            Product::from_api("phone_booth"),
            Product::Other("phone_booth".into())
        );
    }

    #[test]
    fn product_order() {
        let mut v = [
            Product::from_api("zeta"),
            Product::MeetingRoom,
            Product::from_api("alpha"),
            Product::FlexDesk,
        ];
        v.sort_by(|a, b| a.sort_key().cmp(&b.sort_key()));
        let names: Vec<_> = v.iter().map(|p| p.as_str()).collect();
        assert_eq!(names, ["flex_desk", "meeting_room", "alpha", "zeta"]);
    }

    #[test]
    fn currency_and_sort() {
        assert_eq!("usd".parse::<Currency>().unwrap(), Currency::Usd);
        assert_eq!(
            "ves".parse::<Currency>().unwrap(),
            Currency::Other("VES".into())
        );
        assert!("euro".parse::<Currency>().is_err());
        assert_eq!("price_asc".parse::<Sort>().unwrap(), Sort::PriceAsc);
        assert_eq!("DE".parse::<Locale>().unwrap(), Locale::De);
        let e = "fr".parse::<Locale>().unwrap_err();
        assert_eq!(
            e.to_string(),
            "invalid locale \"fr\" (expected one of: en, es, de)"
        );
    }
}
