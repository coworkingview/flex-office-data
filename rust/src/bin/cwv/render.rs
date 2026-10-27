//! Turning rows into tables, CSV and JSON.

use comfy_table::{presets, Attribute, Cell, CellAlignment, Color, ContentArrangement, Table};
use coworkingview::{CityRow, Dataset, PricingRow, RateRow, Space, SpaceRow};
use serde::Serialize;

/// Output being assembled: stdout bytes plus stderr notes (attribution).
#[derive(Default)]
pub struct Output {
    pub stdout: String,
    pub stderr: Vec<String>,
}

pub struct Style {
    pub color: bool,
}

impl Style {
    fn header(&self, cols: &[&str]) -> Vec<Cell> {
        cols.iter()
            .map(|c| {
                let cell = Cell::new(c);
                if self.color {
                    cell.add_attribute(Attribute::Bold)
                } else {
                    cell
                }
            })
            .collect()
    }

    fn dim(&self, cell: Cell) -> Cell {
        if self.color {
            cell.add_attribute(Attribute::Dim)
        } else {
            cell
        }
    }

    fn fg(&self, cell: Cell, color: Color) -> Cell {
        if self.color {
            cell.fg(color)
        } else {
            cell
        }
    }
}

fn table() -> Table {
    let mut t = Table::new();
    t.load_style(presets::UTF8_FULL_CONDENSED.with_rounded_corners())
        .set_content_arrangement(ContentArrangement::Dynamic);
    t
}

fn right(t: &mut Table, cols: &[usize]) {
    for &i in cols {
        if let Some(c) = t.column_mut(i) {
            c.set_cell_alignment(CellAlignment::Right);
        }
    }
}

const DASH: &str = "—";

/// `1453.0, "AED"` → `1,453 AED`; `12.5` → `12.50`.
pub fn money(amount: f64, currency: Option<&str>) -> String {
    let n = group(amount);
    match currency {
        Some(c) if !c.is_empty() => format!("{n} {c}"),
        _ => n,
    }
}

fn opt_money(amount: Option<f64>, currency: Option<&str>) -> String {
    amount.map_or_else(|| DASH.into(), |a| money(a, currency))
}

fn group(amount: f64) -> String {
    let neg = amount < 0.0;
    let a = amount.abs();
    let (int, frac) = if a.fract() == 0.0 {
        (format!("{a:.0}"), String::new())
    } else {
        let s = format!("{a:.2}");
        let (i, f) = s.split_once('.').unwrap_or((&s, "00"));
        (i.to_string(), format!(".{f}"))
    };
    let mut out = String::new();
    for (i, ch) in int.chars().enumerate() {
        if i > 0 && (int.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    format!("{}{out}{frac}", if neg { "-" } else { "" })
}

fn opt_int(v: Option<u64>) -> String {
    v.map_or_else(|| DASH.into(), group_int)
}

fn group_int(v: u64) -> String {
    group(v as f64)
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

pub fn rates_table(ds: &Dataset<Vec<RateRow>>, s: &Style) -> Output {
    let mut out = Output::default();
    if ds.is_empty() {
        out.stderr.push("No figures match these filters.".into());
        attribution(&mut out, ds);
        return out;
    }
    let mut t = table();
    t.set_header(s.header(&[
        "City",
        "Product",
        "Per",
        "Median",
        "P25",
        "P75",
        "Prices",
        "Spaces",
        "Operators",
    ]));
    let mut prev_city: Option<&str> = None;
    let mut any_low = false;
    for r in ds.iter() {
        let cur = Some(r.currency.as_str());
        let city = if prev_city == Some(r.city_slug.as_str()) {
            String::new()
        } else {
            r.city_name.clone()
        };
        prev_city = Some(&r.city_slug);
        any_low |= r.low_confidence;
        let n = if r.low_confidence {
            format!("{}*", r.sample_size)
        } else {
            format!("{} ", r.sample_size)
        };
        let mut row = vec![
            Cell::new(city),
            Cell::new(r.product.label()),
            Cell::new(r.unit.map_or(DASH, |u| u.as_str())),
            Cell::new(money(r.median, cur)),
            Cell::new(opt_money(r.p25, cur)),
            Cell::new(opt_money(r.p75, cur)),
            Cell::new(n),
            Cell::new(opt_int(r.property_count)),
            Cell::new(opt_int(r.operator_count)),
        ];
        if r.low_confidence {
            row = row.into_iter().map(|c| s.dim(c)).collect();
        }
        t.add_row(row);
    }
    right(&mut t, &[3, 4, 5, 6, 7, 8]);
    out.stdout = format!("{t}\n");
    if any_low {
        out.stderr
            .push("* fewer than 10 prices: treat as indicative.".into());
    }
    attribution(&mut out, ds);
    out
}

pub fn cities_table(ds: &Dataset<Vec<CityRow>>, s: &Style) -> Output {
    let mut out = Output::default();
    if ds.is_empty() {
        out.stderr.push("No cities match these filters.".into());
        attribution(&mut out, ds);
        return out;
    }
    let mut t = table();
    t.set_header(s.header(&[
        "City",
        "Country",
        "Spaces",
        "Operators",
        "Entry median",
        "Entry range",
        "P25",
        "P75",
        "Prices",
    ]));
    for c in ds.iter() {
        let cur = c.currency.as_deref();
        let range = match (c.entry_min, c.entry_max) {
            (Some(lo), Some(hi)) => format!("{} – {}", group(lo), money(hi, cur)),
            _ => DASH.into(),
        };
        let row = if c.published {
            vec![
                Cell::new(&c.city_name),
                Cell::new(c.country_code.as_deref().unwrap_or(DASH)),
                Cell::new(opt_int(c.property_count)),
                Cell::new(opt_int(c.operator_count)),
                Cell::new(opt_money(c.entry_median, cur)),
                Cell::new(range),
                Cell::new(opt_money(c.p25, cur)),
                Cell::new(opt_money(c.p75, cur)),
                Cell::new(opt_int(c.sample_size)),
            ]
        } else {
            let mut row = vec![
                Cell::new(&c.city_name),
                Cell::new(c.country_code.as_deref().unwrap_or(DASH)),
                Cell::new("not published yet"),
            ];
            row.extend((0..6).map(|_| Cell::new("")));
            row.into_iter().map(|c| s.dim(c)).collect()
        };
        t.add_row(row);
    }
    right(&mut t, &[2, 3, 4, 5, 6, 7, 8]);
    out.stdout = format!("{t}\n");
    attribution(&mut out, ds);
    out
}

pub fn spaces_table(ds: &Dataset<Vec<SpaceRow>>, s: &Style) -> Output {
    let mut out = Output::default();
    if ds.is_empty() {
        out.stderr.push("No spaces match these filters.".into());
        attribution(&mut out, ds);
        return out;
    }
    let mut t = table();
    t.set_header(s.header(&["Space", "Operator", "Zone", "Price vs city", "Slug"]));
    for r in ds.iter() {
        t.add_row(vec![
            Cell::new(&r.title),
            Cell::new(r.operator_name.as_deref().unwrap_or(DASH)),
            Cell::new(r.zone_slug.as_deref().unwrap_or(DASH)),
            verdict(r.market_verdict.as_deref(), s),
            s.dim(Cell::new(&r.slug)),
        ]);
    }
    out.stdout = format!("{t}\n");
    out.stderr.push(format!(
        "{} space{}. Details and prices: cwv space <slug>",
        ds.len(),
        if ds.len() == 1 { "" } else { "s" }
    ));
    attribution(&mut out, ds);
    out
}

fn verdict(v: Option<&str>, s: &Style) -> Cell {
    match v {
        Some("below") => s.fg(Cell::new("below"), Color::Green),
        Some("above") => s.fg(Cell::new("above"), Color::Yellow),
        Some(other) => Cell::new(other),
        None => Cell::new(DASH),
    }
}

pub fn space_table(ds: &Dataset<Space>, s: &Style) -> Output {
    let mut out = Output::default();
    let sp = &ds.data;

    let mut info = table();
    info.load_style(presets::NOTHING)
        .set_content_arrangement(ContentArrangement::Dynamic);
    let key = |k: &str| {
        let c = Cell::new(k);
        if s.color {
            c.add_attribute(Attribute::Bold)
        } else {
            c
        }
    };
    let mut kv = |k: &str, v: String| {
        info.add_row(vec![key(k), Cell::new(v)]);
    };
    kv("Space", sp.title.clone());
    if let Some(op) = &sp.operator_name {
        kv("Operator", op.clone());
    }
    if let Some(a) = &sp.address {
        kv("Address", a.clone());
    }
    let place: Vec<&str> = [sp.zone_slug.as_deref(), sp.city_slug.as_deref()]
        .into_iter()
        .flatten()
        .collect();
    if !place.is_empty() {
        kv("Area", place.join(", "));
    }
    if let Some(c) = sp.capacity {
        kv("Capacity", format!("{c} people"));
    }
    if let (Some(v), Some(m)) = (&sp.market_verdict, sp.market_median) {
        let n = sp
            .market_sample_size
            .map(|n| format!(", {n} prices"))
            .unwrap_or_default();
        let cur = sp.pricing.iter().find_map(|p| p.currency.as_deref());
        kv(
            "Price vs city",
            format!("{v} the city median ({}{n})", money(m, cur)),
        );
    }
    if !sp.amenities.is_empty() {
        kv("Amenities", sp.amenities.join(", ").replace('_', " "));
    }
    kv("Link", sp.url.clone());
    if let Some(u) = &sp.updated_at {
        kv("Updated", u.get(..10).unwrap_or(u).to_string());
    }
    out.stdout = format!("{info}\n");

    if !sp.pricing.is_empty() {
        let mut t = table();
        t.set_header(s.header(&["Product", "Offer", "Price", "Per", "People"]));
        for p in &sp.pricing {
            t.add_row(pricing_row(p, s));
        }
        right(&mut t, &[2]);
        out.stdout.push('\n');
        out.stdout.push_str(&format!("{t}\n"));
    }
    attribution(&mut out, ds);
    out
}

fn pricing_row(p: &PricingRow, s: &Style) -> Vec<Cell> {
    let price = match p.price {
        Some(a) if !p.price_on_request => Cell::new(money(a, p.currency.as_deref())),
        _ => s.dim(Cell::new("on request")),
    };
    let people = match (p.min_capacity, p.max_capacity) {
        (Some(a), Some(b)) if a == b => a.to_string(),
        (Some(a), Some(b)) => format!("{a}–{b}"),
        (Some(a), None) => format!("{a}+"),
        (None, Some(b)) => format!("up to {b}"),
        (None, None) => DASH.into(),
    };
    vec![
        Cell::new(p.product.label()),
        Cell::new(&p.title),
        price,
        Cell::new(&p.billing_period),
        Cell::new(people),
    ]
}

fn attribution<T>(out: &mut Output, ds: &Dataset<T>) {
    if let Some(a) = &ds.attribution {
        out.stderr.push(a.clone());
    }
    if let Some(l) = &ds.license {
        match &ds.as_of {
            Some(d) => out.stderr.push(format!("License: {l} (as of {d})")),
            None => out.stderr.push(format!("License: {l}")),
        }
    }
    if let Some(n) = &ds.notice {
        out.stderr.push(n.clone());
    }
}

// ---------------------------------------------------------------------------
// CSV and JSON
// ---------------------------------------------------------------------------

pub fn csv<R: coworkingview::csv::CsvRow, T>(rows: &[R], ds: &Dataset<T>) -> Output {
    let mut buf = Vec::new();
    coworkingview::csv::write(&mut buf, rows).expect("writing to memory");
    let mut out = Output {
        stdout: String::from_utf8(buf).expect("CSV is UTF-8"),
        stderr: Vec::new(),
    };
    attribution(&mut out, ds);
    out
}

#[derive(Serialize)]
struct Envelope<'a, R: Serialize> {
    attribution: &'a Option<String>,
    license: &'a Option<String>,
    as_of: &'a Option<String>,
    notice: &'a Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    space: Option<serde_json::Value>,
    rows: R,
}

pub fn json<R: Serialize, T>(rows: R, ds: &Dataset<T>, space: Option<serde_json::Value>) -> Output {
    let env = Envelope {
        attribution: &ds.attribution,
        license: &ds.license,
        as_of: &ds.as_of,
        notice: &ds.notice,
        space,
        rows,
    };
    let mut s = serde_json::to_string_pretty(&env).expect("rows serialize");
    s.push('\n');
    Output {
        stdout: s,
        stderr: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn money_format() {
        assert_eq!(money(1453.0, Some("AED")), "1,453 AED");
        assert_eq!(money(214.0, Some("EUR")), "214 EUR");
        assert_eq!(money(1234567.5, None), "1,234,567.50");
        assert_eq!(money(-1000.0, Some("EUR")), "-1,000 EUR");
        assert_eq!(group_int(85), "85");
    }
}
