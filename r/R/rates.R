fetch_market_rates <- function(city, country, currency, locale) {
  cwv_get("v1/market/rates", list(
    locale = locale,
    city = city,
    country = country,
    currency = currency
  ))
}

index_attrs <- function(data) {
  list(
    attribution = as_chr(data$attribution),
    license = as_chr(data$licenseUrl),
    as_of = as_chr(data$asOf)
  )
}

#' CoworkingView Price Index: flexible office prices by city
#'
#' Downloads the CoworkingView Price Index and returns it as a tidy data
#' frame with one row per city and product. Monthly products (flex desk,
#' fixed desk, private office, ...) come with quartiles; day passes are
#' priced per day and meeting rooms per hour. New aggregates published by
#' the API appear as new `product` values without a package update.
#'
#' The Price Index is licensed under CC BY 4.0. The attribution text you must
#' reproduce when you publish the figures travels with the result; read it
#' with [cwv_attribution()].
#'
#' @param city Optional city slug, such as `"berlin"` or `"madrid"`. See
#'   [cwv_cities()] for the available slugs.
#' @param country Optional ISO 3166-1 alpha-2 country code, such as `"DE"`.
#' @param currency Optional currency to present prices in. One of `"EUR"`,
#'   `"GBP"`, `"USD"`, `"CHF"` or `"AED"`; by default each city is priced in
#'   its local currency. Converted prices are approximate. `"VES"` is passed
#'   through to the API, which rejects it for most cities.
#' @param locale Language of city names: `"en"` (default), `"es"` or `"de"`.
#'
#' @return A data frame (a tibble if the \pkg{tibble} package is installed)
#'   with one row per city and product, ordered by `city_slug` and then by
#'   product (`flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`,
#'   `day_pass`, `meeting_room`, `event_space`, `virtual_office`,
#'   `membership`, then any other product alphabetically):
#'
#'   | Column | Type | Description |
#'   |---|---|---|
#'   | `city_slug` | character | City identifier. |
#'   | `city_name` | character | City name in `locale`. |
#'   | `country_code` | character | ISO 3166-1 alpha-2 country code. |
#'   | `currency` | character | Currency of the prices. |
#'   | `product` | character | Product, such as `flex_desk` or `day_pass`. |
#'   | `unit` | character | Price unit: `month`, `day` or `hour` (`NA` if unknown). |
#'   | `median` | double | Median price. |
#'   | `p25` | double | 25th percentile (`NA` when not published). |
#'   | `p75` | double | 75th percentile (`NA` when not published). |
#'   | `sample_size` | integer | Number of prices behind the figure. |
#'   | `property_count` | integer | Number of spaces behind the figure. |
#'   | `operator_count` | integer | Number of operators behind the figure. |
#'   | `low_confidence` | logical | `TRUE` when `sample_size` is below 10. |
#'   | `as_of` | character | ISO 8601 timestamp of the index. |
#'
#'   The result carries the attributes `attribution`, `license` (the licence
#'   URL) and `as_of`. If the API cannot be reached, a message is shown and
#'   `NULL` is returned invisibly.
#'
#' @seealso [cwv_cities()] for one row per city, [cwv_attribution()] to read
#'   the licence attribution, and
#'   <https://coworkingview.com/en/tools/price-index> for the methodology.
#' @family price index
#' @export
#' @examplesIf interactive()
#' rates <- cwv_rates(city = "berlin")
#' rates[, c("product", "unit", "median", "p25", "p75")]
#'
#' # Prices converted to US dollars
#' cwv_rates(city = "madrid", currency = "USD")
#'
#' # Always cite the source when you publish the figures
#' cwv_attribution(rates)
cwv_rates <- function(city = NULL, country = NULL, currency = NULL,
                      locale = "en") {
  check_string(city, "city")
  check_string(country, "country")
  currency <- check_currency(currency)
  locale <- check_locale(locale)
  body <- fetch_market_rates(city, country, currency, locale)
  if (is.null(body)) {
    return(invisible(NULL))
  }
  as_output(parse_rates(body$data), index_attrs(body$data))
}

#' Cities covered by the CoworkingView Price Index
#'
#' Returns one row per city known to the Price Index, with city-level
#' summary figures. Cities that do not yet have enough prices to be
#' published are included with `published = FALSE` and empty figures.
#'
#' @inheritParams cwv_rates
#'
#' @return A data frame (a tibble if \pkg{tibble} is installed) with one row
#'   per city, published cities first, then ordered by `city_slug`:
#'
#'   | Column | Type | Description |
#'   |---|---|---|
#'   | `city_slug` | character | City identifier, usable in [cwv_rates()] and [cwv_spaces()]. |
#'   | `city_name` | character | City name in `locale`. |
#'   | `country_code` | character | ISO 3166-1 alpha-2 country code. |
#'   | `currency` | character | Currency of the prices. |
#'   | `published` | logical | Whether the city's figures are published. |
#'   | `property_count` | integer | Number of spaces with prices. |
#'   | `operator_count` | integer | Number of operators with prices. |
#'   | `entry_median` | double | Median of the cheapest monthly option per space. |
#'   | `entry_min` | double | Lowest cheapest monthly option. |
#'   | `entry_max` | double | Highest cheapest monthly option. |
#'   | `p25` | double | City-level 25th percentile of monthly prices. |
#'   | `p75` | double | City-level 75th percentile of monthly prices. |
#'   | `sample_size` | integer | Number of monthly prices (`NA` if unpublished). |
#'   | `as_of` | character | ISO 8601 timestamp of the index. |
#'
#'   The result carries the attributes `attribution`, `license` and `as_of`.
#'   If the API cannot be reached, a message is shown and `NULL` is returned
#'   invisibly.
#'
#' @seealso [cwv_rates()] for figures by product, [cwv_attribution()].
#' @family price index
#' @export
#' @examplesIf interactive()
#' cities <- cwv_cities()
#' cities[cities$published, c("city_slug", "entry_median", "sample_size")]
cwv_cities <- function(country = NULL, currency = NULL, locale = "en") {
  check_string(country, "country")
  currency <- check_currency(currency)
  locale <- check_locale(locale)
  body <- fetch_market_rates(NULL, country, currency, locale)
  if (is.null(body)) {
    return(invisible(NULL))
  }
  as_output(parse_cities(body$data), index_attrs(body$data))
}
