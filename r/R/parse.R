# Pure parsers: parsed JSON (lists) -> data frames. They mirror
# spec/tools/make_golden.py, the reference reading of SPEC.md.


stat_units <- c(
  day_pass = "day", meeting_room = "hour", event_space = "hour",
  virtual_office = "month"
)
workspace_path <- c(en = "workspace", es = "oficina", de = "buero")
low_confidence_below <- 10L

rates_template <- list(
  city_slug = character(), city_name = character(),
  country_code = character(), currency = character(),
  product = character(), unit = character(),
  median = numeric(), p25 = numeric(), p75 = numeric(),
  sample_size = integer(), property_count = integer(),
  operator_count = integer(), low_confidence = logical(),
  as_of = character()
)

cities_template <- list(
  city_slug = character(), city_name = character(),
  country_code = character(), currency = character(),
  published = logical(),
  property_count = integer(), operator_count = integer(),
  entry_median = numeric(), entry_min = numeric(), entry_max = numeric(),
  p25 = numeric(), p75 = numeric(),
  sample_size = integer(), as_of = character()
)

spaces_template <- list(
  slug = character(), title = character(),
  city_slug = character(), zone_slug = character(),
  operator_slug = character(), operator_name = character(),
  country_code = character(), lat = numeric(), lng = numeric(),
  featured = logical(), market_verdict = character(),
  market_median = numeric(), market_sample_size = integer(),
  url = character(), updated_at = character()
)

pricing_template <- list(
  product = character(), title = character(), price = numeric(),
  currency = character(), billing_period = character(),
  price_on_request = logical(),
  min_capacity = integer(), max_capacity = integer()
)

snake_case <- function(key) {
  tolower(gsub("(?<!^)(?=[A-Z])", "_", key, perl = TRUE))
}

is_stat <- function(value) {
  is.list(value) && !is.null(names(value)) &&
    all(c("median", "sampleSize") %in% names(value))
}

# Sort rows by city slug (code-point order), then the spec's product order,
# then unknown products alphabetically.
order_rates <- function(df) {
  known <- match(df$product, cwv_products)
  group <- ifelse(is.na(known), 1L, 0L)
  rank <- ifelse(is.na(known), 0L, known)
  extra <- ifelse(is.na(known), df$product, "")
  df[order(df$city_slug, group, rank, extra, method = "radix"), , drop = FALSE]
}

stat_row <- function(base, product, unit, item) {
  c(base, list(
    product = product,
    unit = unit,
    median = amount(item$median),
    p25 = amount(item$p25),
    p75 = amount(item$p75),
    sample_size = as_int(item$sampleSize),
    property_count = as_int(item$propertyCount),
    operator_count = as_int(item$operatorCount)
  ))
}

parse_rates <- function(data) {
  rows <- list()
  for (city in data$cities) {
    base <- list(
      city_slug = as_chr(city$city$slug),
      city_name = as_chr(city$city$name),
      country_code = as_chr(city$countryCode),
      currency = as_chr(city$currency)
    )
    monthly <- city$figures
    if (length(monthly) == 0L) monthly <- city$byType
    for (item in monthly) {
      rows[[length(rows) + 1L]] <-
        stat_row(base, as_chr(item$optionType), "month", item)
    }
    for (key in names(city)) {
      value <- city[[key]]
      if (!is_stat(value)) next
      product <- snake_case(key)
      unit <- if (product %in% names(stat_units)) {
        unname(stat_units[[product]])
      } else {
        NA_character_
      }
      rows[[length(rows) + 1L]] <- stat_row(base, product, unit, value)
    }
  }
  as_of <- as_chr(data$asOf)
  rows <- lapply(rows, function(r) {
    r$low_confidence <- !is.na(r$sample_size) &&
      r$sample_size < low_confidence_below
    r$as_of <- as_of
    r
  })
  df <- rows_to_df(rows, rates_template)
  df <- order_rates(df)
  rownames(df) <- NULL
  df
}

parse_cities <- function(data) {
  as_of <- as_chr(data$asOf)
  rows <- list()
  for (city in data$cities) {
    rows[[length(rows) + 1L]] <- list(
      city_slug = as_chr(city$city$slug),
      city_name = as_chr(city$city$name),
      country_code = as_chr(city$countryCode),
      currency = as_chr(city$currency),
      published = TRUE,
      property_count = as_int(city$propertyCount),
      operator_count = as_int(city$operatorCount),
      entry_median = amount(city$entryMedian),
      entry_min = amount(city$entryMin),
      entry_max = amount(city$entryMax),
      p25 = amount(city$p25),
      p75 = amount(city$p75),
      sample_size = as_int(city$sampleSize),
      as_of = as_of
    )
  }
  for (city in data$unpublished) {
    rows[[length(rows) + 1L]] <- list(
      city_slug = as_chr(city$city$slug),
      city_name = as_chr(city$city$name),
      country_code = as_chr(city$countryCode),
      currency = as_chr(city$currency),
      published = FALSE,
      property_count = NA_integer_,
      operator_count = NA_integer_,
      entry_median = NA_real_,
      entry_min = NA_real_,
      entry_max = NA_real_,
      p25 = NA_real_,
      p75 = NA_real_,
      sample_size = NA_integer_,
      as_of = as_of
    )
  }
  df <- rows_to_df(rows, cities_template)
  df <- df[order(!df$published, df$city_slug, method = "radix"), , drop = FALSE]
  rownames(df) <- NULL
  df
}

space_url <- function(slug, locale) {
  sprintf(
    "https://coworkingview.com/%s/%s/%s",
    locale, workspace_path[[locale]], slug
  )
}

space_fields <- function(card, locale) {
  market <- card$marketPosition
  list(
    slug = as_chr(card$slug),
    title = as_chr(card$title),
    city_slug = as_chr(field(card$city, "slug")),
    zone_slug = as_chr(field(card$zone, "slug")),
    operator_slug = as_chr(field(card$operator, "slug")),
    operator_name = as_chr(field(card$operator, "name")),
    country_code = as_chr(card$countryCode),
    lat = as_num(field(card$coordinates, "lat")),
    lng = as_num(field(card$coordinates, "lng")),
    featured = as_lgl(card$featured),
    market_verdict = as_chr(field(market, "verdict")),
    market_median = amount(field(market, "median")),
    market_sample_size = as_int(field(market, "sampleSize")),
    url = space_url(as_chr(card$slug), locale),
    updated_at = as_chr(card$updatedAt)
  )
}

parse_spaces <- function(cards, locale) {
  rows <- lapply(cards, space_fields, locale = locale)
  rows_to_df(rows, spaces_template)
}

parse_pricing <- function(detail) {
  rows <- lapply(detail$pricingOptions, function(option) {
    price <- option$price
    list(
      product = as_chr(option$optionType),
      title = as_chr(option$title),
      price = amount(price),
      currency = if (is.list(price)) as_chr(price$currency) else NA_character_,
      billing_period = as_chr(option$billingPeriod),
      price_on_request = as_lgl(option$priceOnRequest),
      min_capacity = as_int(option$minCapacity),
      max_capacity = as_int(option$maxCapacity)
    )
  })
  rows_to_df(rows, pricing_template)
}

parse_space <- function(detail, locale) {
  out <- space_fields(detail, locale)
  out$url <- as_chr(detail$webUrl %||% out$url)
  out$address <- as_chr(detail$address)
  out$capacity <- as_int(detail$capacity)
  out$amenities <- as.character(unlist(detail$amenities %||% list()))
  out$pricing <- parse_pricing(detail)
  out
}
