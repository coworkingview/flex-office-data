//! Command-line arguments.

use clap::builder::styling::{AnsiColor, Effects, Styles};
use clap::builder::{PossibleValuesParser, TypedValueParser};
use clap::{Args, Parser, Subcommand, ValueEnum};
use coworkingview::{Currency, Locale, Product, Sort};

const STYLES: Styles = Styles::styled()
    .header(AnsiColor::Green.on_default().effects(Effects::BOLD))
    .usage(AnsiColor::Green.on_default().effects(Effects::BOLD))
    .literal(AnsiColor::Cyan.on_default().effects(Effects::BOLD))
    .placeholder(AnsiColor::Cyan.on_default())
    .valid(AnsiColor::Cyan.on_default())
    .invalid(AnsiColor::Yellow.on_default())
    .error(AnsiColor::Red.on_default().effects(Effects::BOLD));

const ABOUT: &str = "Flexible-office prices by city, and coworking search, from CoworkingView";

const LONG_ABOUT: &str = "\
Flexible-office prices by city, and coworking search, from CoworkingView.

`cwv` reads CoworkingView's public API (no key needed). `cwv rates` and
`cwv cities` print the CoworkingView Price Index — median, 25th and 75th
percentile prices for flex desks, fixed desks and private offices per month,
day passes per day and meeting rooms per hour — licensed CC BY 4.0.
`cwv spaces` and `cwv space` search the catalogue of coworking spaces,
private offices, meeting rooms, event spaces and virtual offices.

The attribution required by the licence is printed to stderr after tables and
CSV, and included in JSON output.";

const EXAMPLES: &str = "\
Examples:
  cwv rates --city berlin                   Price Index for Berlin
  cwv rates --product flex_desk -f csv      Flex-desk medians of every city as CSV
  cwv cities                                Cities covered, with entry prices
  cwv spaces --city berlin --zone mitte     Spaces in Berlin-Mitte
  cwv space sankt-oberholz-rosenthaler-berlin
                                            One space and its prices

Learn more: https://coworkingview.com/en/tools/price-index";

#[derive(Debug, Parser)]
#[command(
    name = "cwv",
    version,
    about = ABOUT,
    long_about = LONG_ABOUT,
    after_help = EXAMPLES,
    styles = STYLES,
    propagate_version = true,
    disable_help_subcommand = true,
    arg_required_else_help = true,
    max_term_width = 100
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,

    #[command(flatten)]
    pub global: Global,
}

#[derive(Debug, Args)]
pub struct Global {
    /// Output format
    #[arg(
        long,
        short = 'f',
        global = true,
        value_enum,
        default_value_t = Format::Table,
        help_heading = "Output"
    )]
    pub format: Format,

    /// Language of names and links
    #[arg(
        long,
        short = 'l',
        global = true,
        value_name = "LOCALE",
        value_parser = PossibleValuesParser::new(Locale::NAMES).map(|s| s.parse::<Locale>().unwrap()),
        help_heading = "Output"
    )]
    pub locale: Option<Locale>,

    /// Disable colours (also honoured: the NO_COLOR environment variable)
    #[arg(long, global = true, help_heading = "Output")]
    pub no_color: bool,

    #[arg(
        long,
        help = "API base URL (default: https://api.coworkingview.com)",
        global = true,
        value_name = "URL",
        env = "COWORKINGVIEW_API_URL",
        default_value = coworkingview::DEFAULT_BASE_URL,
        hide_default_value = true,
        hide_env_values = true,
        help_heading = "Connection"
    )]
    pub api_url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Format {
    /// Aligned table for humans
    Table,
    /// CSV with a header row (attribution on stderr)
    Csv,
    /// JSON object: {attribution, license, as_of, notice, rows}
    Json,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Price Index: median prices per city and product
    #[command(
        long_about = "\
Price Index: median prices per city and product.

One row per city × product. Flex desks, fixed desks and private offices are
priced per month, day passes per day, meeting rooms per hour. Figures based
on fewer than 10 prices are marked with * and should be read as indicative.

Licensed CC BY 4.0 — the attribution is printed to stderr.",
        after_help = "\
Examples:
  cwv rates
  cwv rates --city berlin
  cwv rates --country ES --currency USD
  cwv rates --product flex_desk,private_office --format csv > rates.csv"
    )]
    Rates(RatesArgs),

    /// Cities in the Price Index, with entry prices
    #[command(
        long_about = "\
Cities in the Price Index, with entry prices.

One row per city: how many spaces and operators were priced, the median and
range of each space's cheapest monthly option, and the city-wide 25th–75th
percentile. Cities without enough data yet are listed as not published.",
        after_help = "\
Examples:
  cwv cities
  cwv cities --currency GBP
  cwv cities --format json | jq '.rows[] | select(.published) | .city_slug'"
    )]
    Cities(CitiesArgs),

    /// Search coworking spaces, offices, meeting rooms and virtual offices
    #[command(
        long_about = "\
Search coworking spaces, private offices, meeting rooms, event spaces and
virtual offices.

Returns at most 200 spaces per call (50 by default): the catalogue may be
searched and linked to, not bulk-copied. Results are in random order unless
--sort is given; pages of one call never overlap.",
        after_help = "\
Examples:
  cwv spaces --city berlin
  cwv spaces --city madrid --product private_office --min-capacity 4
  cwv spaces --city berlin --product day_pass --max-price 30 --sort price-asc
  cwv spaces --operator regus --limit 200 --format csv"
    )]
    Spaces(SpacesArgs),

    /// One space: address, amenities and its prices
    #[command(after_help = "\
Examples:
  cwv space sankt-oberholz-rosenthaler-berlin
  cwv space sankt-oberholz-rosenthaler-berlin --format csv   (pricing table)
  cwv space sankt-oberholz-rosenthaler-berlin --locale de")]
    Space(SpaceArgs),

    /// Print a shell completion script
    #[command(after_help = "\
Examples:
  cwv completions bash > ~/.local/share/bash-completion/completions/cwv
  cwv completions zsh  > ~/.zfunc/_cwv
  cwv completions fish > ~/.config/fish/completions/cwv.fish
  cwv completions powershell >> $PROFILE")]
    Completions {
        /// Shell to generate the script for
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },

    /// Print the man page (roff) to stdout
    #[command(hide = true)]
    Man,
}

fn product_parser() -> impl TypedValueParser<Value = Product> {
    PossibleValuesParser::new(Product::NAMES).map(|s| s.parse::<Product>().unwrap())
}

fn parse_slug(s: &str) -> Result<String, String> {
    if coworkingview::is_valid_slug(s) {
        Ok(s.to_string())
    } else {
        Err("a slug starts with a letter or digit and contains only letters, digits, '.', '_' and '-'".into())
    }
}

fn parse_currency(s: &str) -> Result<Currency, String> {
    s.parse::<Currency>().map_err(|_| {
        format!(
            "expected a 3-letter currency code such as {}",
            Currency::NAMES.join(", ")
        )
    })
}

#[derive(Debug, Args)]
pub struct RatesArgs {
    /// Only this city (slug, e.g. berlin)
    #[arg(long, value_name = "SLUG")]
    pub city: Option<String>,

    /// Only this country (ISO code, e.g. DE)
    #[arg(long, value_name = "CODE")]
    pub country: Option<String>,

    /// Show prices in this currency [EUR, GBP, USD, CHF, AED]
    #[arg(long, value_name = "CODE", value_parser = parse_currency)]
    pub currency: Option<Currency>,

    /// Only these products (repeat or separate with commas)
    #[arg(long, short = 'p', value_name = "PRODUCT", value_delimiter = ',', value_parser = product_parser())]
    pub product: Vec<Product>,
}

#[derive(Debug, Args)]
pub struct CitiesArgs {
    /// Only this country (ISO code, e.g. DE)
    #[arg(long, value_name = "CODE")]
    pub country: Option<String>,

    /// Show prices in this currency [EUR, GBP, USD, CHF, AED]
    #[arg(long, value_name = "CODE", value_parser = parse_currency)]
    pub currency: Option<Currency>,
}

#[derive(Debug, Args)]
pub struct SpacesArgs {
    /// City (slug, e.g. berlin)
    #[arg(long, value_name = "SLUG")]
    pub city: Option<String>,

    /// Country (ISO code, e.g. DE)
    #[arg(long, value_name = "CODE")]
    pub country: Option<String>,

    /// District (slug, e.g. mitte)
    #[arg(long, value_name = "SLUG")]
    pub zone: Option<String>,

    /// Operator (slug, e.g. regus)
    #[arg(long, value_name = "SLUG")]
    pub operator: Option<String>,

    /// Only spaces offering this product
    #[arg(long, short = 'p', value_name = "PRODUCT", value_parser = product_parser())]
    pub product: Option<Product>,

    /// Only spaces with room for at least this many people
    #[arg(long, value_name = "PEOPLE")]
    pub min_capacity: Option<u32>,

    /// Lowest price (in --currency)
    #[arg(long, value_name = "AMOUNT")]
    pub min_price: Option<f64>,

    /// Highest price (in --currency)
    #[arg(long, value_name = "AMOUNT")]
    pub max_price: Option<f64>,

    /// Currency of --min-price/--max-price
    #[arg(long, value_name = "CODE", value_parser = parse_currency)]
    pub currency: Option<Currency>,

    /// Result order [default: random]
    #[arg(
        long,
        value_name = "ORDER",
        value_parser = PossibleValuesParser::new(Sort::NAMES).map(|s| s.parse::<Sort>().unwrap())
    )]
    pub sort: Option<Sort>,

    /// Seed for the random order, to repeat a search exactly
    #[arg(long, value_name = "N")]
    pub seed: Option<u64>,

    /// Most spaces to return (at most 200)
    #[arg(
        long,
        short = 'n',
        value_name = "N",
        default_value_t = 50,
        value_parser = clap::value_parser!(u16).range(1..=200)
    )]
    pub limit: u16,
}

#[derive(Debug, Args)]
pub struct SpaceArgs {
    /// The space's slug, as printed by `cwv spaces`
    #[arg(value_name = "SLUG", value_parser = parse_slug)]
    pub slug: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn cli_is_well_formed() {
        Cli::command().debug_assert();
    }
}
