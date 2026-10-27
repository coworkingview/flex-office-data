//! CSV output in the kit's shared format: comma-separated, `\n` line ends, a
//! header row, an empty field for null, `true`/`false` for booleans and
//! numbers as the API wrote them.
//!
//! ```
//! use coworkingview::csv;
//! # fn rows() -> Vec<coworkingview::RateRow> { Vec::new() }
//! let mut out = Vec::new();
//! csv::write(&mut out, &rows()).unwrap();
//! assert!(out.starts_with(b"city_slug,city_name,"));
//! ```

use std::io::{self, Write};

use crate::model::{CityRow, PricingRow, RateRow, SpaceRow};

/// A row type with a fixed set of CSV columns.
pub trait CsvRow {
    /// Column names, in order.
    const HEADER: &'static [&'static str];
    /// The row's cells, unquoted, in [`HEADER`](CsvRow::HEADER) order.
    fn fields(&self) -> Vec<String>;
}

/// Writes a header row and one line per row.
pub fn write<W: Write, R: CsvRow>(mut w: W, rows: &[R]) -> io::Result<()> {
    write_record(&mut w, R::HEADER.iter().copied())?;
    for row in rows {
        let fields = row.fields();
        write_record(&mut w, fields.iter().map(String::as_str))?;
    }
    w.flush()
}

fn write_record<'a, W: Write>(w: &mut W, cells: impl Iterator<Item = &'a str>) -> io::Result<()> {
    let mut line = String::new();
    for (i, cell) in cells.enumerate() {
        if i > 0 {
            line.push(',');
        }
        // Minimal quoting, as Python's csv module does it.
        if cell.contains([',', '"', '\n', '\r']) {
            line.push('"');
            line.push_str(&cell.replace('"', "\"\""));
            line.push('"');
        } else {
            line.push_str(cell);
        }
    }
    line.push('\n');
    w.write_all(line.as_bytes())
}

/// Formats a number the way the API (JSON) wrote it: whole numbers without a
/// decimal point, everything else in the shortest form that round-trips.
pub(crate) fn num(x: f64) -> String {
    if x.is_finite() && x.fract() == 0.0 && x.abs() < 9.007_199_254_740_992e15 {
        format!("{}", x as i64)
    } else {
        format!("{x}")
    }
}

fn opt_num(x: Option<f64>) -> String {
    x.map(num).unwrap_or_default()
}

fn opt_int(x: Option<u64>) -> String {
    x.map(|v| v.to_string()).unwrap_or_default()
}

fn opt_str(x: &Option<String>) -> String {
    x.clone().unwrap_or_default()
}

fn opt_bool(x: Option<bool>) -> String {
    x.map(|b| b.to_string()).unwrap_or_default()
}

impl CsvRow for RateRow {
    const HEADER: &'static [&'static str] = &[
        "city_slug",
        "city_name",
        "country_code",
        "currency",
        "product",
        "unit",
        "median",
        "p25",
        "p75",
        "sample_size",
        "property_count",
        "operator_count",
        "low_confidence",
        "as_of",
    ];

    fn fields(&self) -> Vec<String> {
        vec![
            self.city_slug.clone(),
            self.city_name.clone(),
            opt_str(&self.country_code),
            self.currency.clone(),
            self.product.to_string(),
            self.unit.map(|u| u.to_string()).unwrap_or_default(),
            num(self.median),
            opt_num(self.p25),
            opt_num(self.p75),
            self.sample_size.to_string(),
            opt_int(self.property_count),
            opt_int(self.operator_count),
            self.low_confidence.to_string(),
            self.as_of.clone(),
        ]
    }
}

impl CsvRow for CityRow {
    const HEADER: &'static [&'static str] = &[
        "city_slug",
        "city_name",
        "country_code",
        "currency",
        "published",
        "property_count",
        "operator_count",
        "entry_median",
        "entry_min",
        "entry_max",
        "p25",
        "p75",
        "sample_size",
        "as_of",
    ];

    fn fields(&self) -> Vec<String> {
        vec![
            self.city_slug.clone(),
            self.city_name.clone(),
            opt_str(&self.country_code),
            opt_str(&self.currency),
            self.published.to_string(),
            opt_int(self.property_count),
            opt_int(self.operator_count),
            opt_num(self.entry_median),
            opt_num(self.entry_min),
            opt_num(self.entry_max),
            opt_num(self.p25),
            opt_num(self.p75),
            opt_int(self.sample_size),
            self.as_of.clone(),
        ]
    }
}

impl CsvRow for SpaceRow {
    const HEADER: &'static [&'static str] = &[
        "slug",
        "title",
        "city_slug",
        "zone_slug",
        "operator_slug",
        "operator_name",
        "country_code",
        "lat",
        "lng",
        "featured",
        "market_verdict",
        "market_median",
        "market_sample_size",
        "url",
        "updated_at",
    ];

    fn fields(&self) -> Vec<String> {
        vec![
            self.slug.clone(),
            self.title.clone(),
            opt_str(&self.city_slug),
            opt_str(&self.zone_slug),
            opt_str(&self.operator_slug),
            opt_str(&self.operator_name),
            opt_str(&self.country_code),
            opt_num(self.lat),
            opt_num(self.lng),
            opt_bool(self.featured),
            opt_str(&self.market_verdict),
            opt_num(self.market_median),
            opt_int(self.market_sample_size),
            self.url.clone(),
            opt_str(&self.updated_at),
        ]
    }
}

impl CsvRow for PricingRow {
    const HEADER: &'static [&'static str] = &[
        "product",
        "title",
        "price",
        "currency",
        "billing_period",
        "price_on_request",
        "min_capacity",
        "max_capacity",
    ];

    fn fields(&self) -> Vec<String> {
        vec![
            self.product.to_string(),
            self.title.clone(),
            opt_num(self.price),
            opt_str(&self.currency),
            self.billing_period.clone(),
            self.price_on_request.to_string(),
            opt_int(self.min_capacity),
            opt_int(self.max_capacity),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers() {
        assert_eq!(num(1400.0), "1400");
        assert_eq!(num(52.5294539), "52.5294539");
        assert_eq!(num(13.4018374), "13.4018374");
        assert_eq!(num(-0.5), "-0.5");
        assert_eq!(num(209.99), "209.99");
    }

    #[test]
    fn quoting() {
        let mut out = Vec::new();
        write_record(&mut out, ["a,b", "say \"hi\"", "plain", ""].into_iter()).unwrap();
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "\"a,b\",\"say \"\"hi\"\"\",plain,\n"
        );
    }
}
