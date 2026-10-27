//! `cwv` — flexible-office prices by city, and coworking search, from
//! CoworkingView. See `cwv --help`.

mod cli;
mod render;

use std::io::{self, IsTerminal, Write};
use std::process::ExitCode;

use clap::{CommandFactory, Parser};
use coworkingview::{Client, Error, RatesQuery, SpacesQuery};

use cli::{Cli, Command, Format};
use render::{Output, Style};

fn main() -> ExitCode {
    let cli = Cli::parse();
    let color_out = use_color(&cli, io::stdout().is_terminal());
    let color_err = use_color(&cli, io::stderr().is_terminal());

    match run(&cli, color_out) {
        Ok(out) => emit(out, color_err),
        Err(e) => {
            report(&e, color_err);
            ExitCode::from(1)
        }
    }
}

fn use_color(cli: &Cli, tty: bool) -> bool {
    tty && !cli.global.no_color && std::env::var_os("NO_COLOR").is_none_or(|v| v.is_empty())
}

fn run(cli: &Cli, color: bool) -> Result<Output, Error> {
    let g = &cli.global;
    let style = Style { color };
    let mut builder = Client::builder().base_url(&g.api_url);
    if let Some(l) = g.locale {
        builder = builder.locale(l);
    }
    let client = builder.build();

    Ok(match &cli.command {
        Command::Rates(a) => {
            let mut q = RatesQuery::new();
            q.city = a.city.clone();
            q.country = a.country.clone();
            q.currency = a.currency.clone();
            q.products = a.product.clone();
            let ds = client.rates_with(&q)?;
            match g.format {
                Format::Table => render::rates_table(&ds, &style),
                Format::Csv => render::csv(&ds, &ds),
                Format::Json => render::json(&ds.data, &ds, None),
            }
        }
        Command::Cities(a) => {
            let mut q = RatesQuery::new();
            q.country = a.country.clone();
            q.currency = a.currency.clone();
            let ds = client.cities_with(&q)?;
            match g.format {
                Format::Table => render::cities_table(&ds, &style),
                Format::Csv => render::csv(&ds, &ds),
                Format::Json => render::json(&ds.data, &ds, None),
            }
        }
        Command::Spaces(a) => {
            let mut q = SpacesQuery::new().limit(usize::from(a.limit));
            q.city = a.city.clone();
            q.country = a.country.clone();
            q.zone = a.zone.clone();
            q.operator = a.operator.clone();
            q.product = a.product.clone();
            q.min_capacity = a.min_capacity;
            q.min_price = a.min_price;
            q.max_price = a.max_price;
            q.currency = a.currency.clone();
            q.sort = a.sort;
            q.seed = a.seed;
            let ds = client.spaces(&q)?;
            match g.format {
                Format::Table => render::spaces_table(&ds, &style),
                Format::Csv => render::csv(&ds, &ds),
                Format::Json => render::json(&ds.data, &ds, None),
            }
        }
        Command::Space(a) => {
            let ds = client.space(&a.slug)?;
            match g.format {
                Format::Table => render::space_table(&ds, &style),
                Format::Csv => render::csv(&ds.pricing, &ds),
                Format::Json => {
                    let mut v = serde_json::to_value(&ds.data).expect("space serializes");
                    if let Some(o) = v.as_object_mut() {
                        o.remove("pricing");
                    }
                    render::json(&ds.pricing, &ds, Some(v))
                }
            }
        }
        Command::Completions { shell } => {
            let mut buf = Vec::new();
            clap_complete::generate(*shell, &mut Cli::command(), "cwv", &mut buf);
            Output {
                stdout: String::from_utf8_lossy(&buf).into_owned(),
                stderr: Vec::new(),
            }
        }
        Command::Man => {
            let mut buf = Vec::new();
            clap_mangen::Man::new(Cli::command())
                .render(&mut buf)
                .expect("writing to memory");
            Output {
                stdout: String::from_utf8_lossy(&buf).into_owned(),
                stderr: Vec::new(),
            }
        }
    })
}

/// Writes stdout, then the attribution notes to stderr. A closed pipe
/// (`cwv rates | head`) is not an error.
fn emit(out: Output, color_err: bool) -> ExitCode {
    let mut stdout = io::stdout().lock();
    match stdout
        .write_all(out.stdout.as_bytes())
        .and_then(|()| stdout.flush())
    {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => return ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("cwv: error: cannot write output: {e}");
            return ExitCode::from(1);
        }
    }
    if !out.stderr.is_empty() {
        let mut stderr = io::stderr().lock();
        let (dim, reset) = if color_err {
            ("\x1b[2m", "\x1b[0m")
        } else {
            ("", "")
        };
        let _ = writeln!(stderr);
        for line in out.stderr {
            let _ = writeln!(stderr, "{dim}{line}{reset}");
        }
    }
    ExitCode::SUCCESS
}

fn report(e: &Error, color: bool) {
    let (red, bold, reset) = if color {
        ("\x1b[31;1m", "\x1b[1m", "\x1b[0m")
    } else {
        ("", "", "")
    };
    let mut stderr = io::stderr().lock();
    let _ = writeln!(stderr, "{red}error:{reset} {e}");
    if let Error::Api(api) = e {
        for f in &api.errors {
            let _ = writeln!(stderr, "  {bold}{}{reset}: {}", f.path, f.message);
        }
        let hint = match api.code.as_str() {
            "NOT_FOUND" => Some("check the slug with `cwv spaces`"),
            "RATE_LIMITED" => Some("the API allows 120 requests per minute; try again shortly"),
            _ if api.status == 429 => {
                Some("the API allows 120 requests per minute; try again shortly")
            }
            _ => None,
        };
        if let Some(h) = hint {
            let _ = writeln!(stderr, "  {bold}hint{reset}: {h}");
        }
    } else if let Error::Network { .. } = e {
        let _ = writeln!(
            stderr,
            "  {bold}hint{reset}: check your connection, or set COWORKINGVIEW_API_URL / --api-url"
        );
    }
}
