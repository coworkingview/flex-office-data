cwv_max_limit <- 200L
cwv_page_size <- 50L

catalogue_attrs <- function(meta) {
  list(
    attribution = as_chr(field(meta$citation, "text")),
    notice = as_chr(meta$catalogueNotice)
  )
}

#' Search the CoworkingView catalogue of flexible workspaces
#'
#' Searches coworking spaces, event spaces, meeting rooms, virtual offices
#' and other flexible workspaces listed on CoworkingView, and returns one row
#' per space with a link to its listing page.
#'
#' The catalogue may be searched and linked, not bulk-copied: a call returns
#' at most 200 spaces, and descriptions, photos and logos (the operators'
#' content) are never returned. Do not loop over cities to rebuild the
#' catalogue; the API's terms forbid systematic extraction.
#'
#' @param city Optional city slug, such as `"berlin"`.
#' @param country Optional ISO 3166-1 alpha-2 country code, such as `"ES"`.
#' @param zone Optional zone (neighbourhood) slug, such as `"mitte"`.
#' @param operator Optional operator slug, such as `"regus"`.
#' @param product Optional product the space must offer. One of
#'   `"flex_desk"`, `"fix_desk"`, `"private_office"`, `"exclusive_bereich"`,
#'   `"day_pass"`, `"meeting_room"`, `"event_space"`, `"virtual_office"` or
#'   `"membership"`.
#' @param min_capacity Optional minimum number of people.
#' @param min_price,max_price Optional price range, in `currency`.
#' @param currency Optional currency for `min_price`, `max_price` and the
#'   market comparison: `"EUR"`, `"GBP"`, `"USD"`, `"CHF"` or `"AED"`.
#' @param sort Order of results: `"random"` (default; fair to all operators),
#'   `"price-asc"`, `"date-desc"` or `"date-asc"`.
#' @param limit Maximum number of spaces to return, between 1 and 200
#'   (default 50).
#' @param locale Language of titles and of the listing URLs: `"en"`
#'   (default), `"es"` or `"de"`.
#' @param seed Optional integer seed for `sort = "random"`. The seed used is
#'   returned in the `seed` attribute; pass it again to reproduce an order.
#'
#' @return A data frame (a tibble if \pkg{tibble} is installed) with one row
#'   per space:
#'
#'   | Column | Type | Description |
#'   |---|---|---|
#'   | `slug` | character | Space identifier, usable in [cwv_space()]. |
#'   | `title` | character | Name of the space. |
#'   | `city_slug` | character | City identifier. |
#'   | `zone_slug` | character | Zone identifier (`NA` when absent). |
#'   | `operator_slug` | character | Operator identifier. |
#'   | `operator_name` | character | Operator name. |
#'   | `country_code` | character | ISO 3166-1 alpha-2 country code. |
#'   | `lat`, `lng` | double | Coordinates (WGS 84). |
#'   | `featured` | logical | Whether the listing is featured. |
#'   | `market_verdict` | character | `below`, `around` or `above` the city median (`NA` when absent). |
#'   | `market_median` | double | City median used for the verdict. |
#'   | `market_sample_size` | integer | Sample size of that median. |
#'   | `url` | character | Listing page on coworkingview.com. |
#'   | `updated_at` | character | ISO 8601 timestamp of the last update. |
#'
#'   The result carries the attributes `attribution` (the citation text),
#'   `notice` (the catalogue terms) and `seed`. If the API cannot be
#'   reached, a message is shown and `NULL` is returned invisibly.
#'
#' @seealso [cwv_space()] for one space and its prices, [cwv_rates()] for the
#'   Price Index, [cwv_attribution()].
#' @family catalogue
#' @export
#' @examplesIf interactive()
#' # Ten spaces in Berlin with a private office, cheapest first
#' cwv_spaces(city = "berlin", product = "private_office",
#'            sort = "price-asc", limit = 10)
#'
#' # Event spaces in Madrid for at least 50 people
#' cwv_spaces(city = "madrid", product = "event_space", min_capacity = 50)
cwv_spaces <- function(city = NULL, country = NULL, zone = NULL,
                       operator = NULL, product = NULL, min_capacity = NULL,
                       min_price = NULL, max_price = NULL, currency = NULL,
                       sort = "random", limit = 50, locale = "en",
                       seed = NULL) {
  check_string(city, "city")
  check_string(country, "country")
  check_string(zone, "zone")
  check_string(operator, "operator")
  product <- check_choice(product, cwv_products, "product")
  check_number(min_capacity, "min_capacity", min = 1, whole = TRUE)
  check_number(min_price, "min_price", min = 0)
  check_number(max_price, "max_price", min = 0)
  currency <- check_currency(currency)
  sort <- check_choice(sort, cwv_sorts, "sort", allow_null = FALSE)
  check_number(limit, "limit", min = 1, whole = TRUE)
  if (is.null(limit)) limit <- 50L
  if (limit > cwv_max_limit) {
    cwv_abort(
      paste0(
        "`limit` must be at most 200. The catalogue may be searched and ",
        "linked, not bulk-copied: its terms forbid systematic extraction ",
        "or re-use of the catalogue database."
      ),
      class = "cwv_input_error"
    )
  }
  limit <- as.integer(limit)
  locale <- check_locale(locale)
  check_number(seed, "seed", whole = TRUE)

  page_size <- min(cwv_page_size, limit)
  query <- list(
    locale = locale, city = city, country = country, zone = zone,
    operator = operator, pricingOptionType = product,
    minCapacity = min_capacity, minPrice = min_price, maxPrice = max_price,
    currency = currency, sortBy = sort, pageSize = page_size,
    seed = if (is.null(seed)) NULL else format(seed, scientific = FALSE)
  )

  cards <- list()
  meta <- NULL
  page <- 1L
  repeat {
    query$page <- page
    body <- cwv_get("v1/properties", query)
    if (is.null(body)) {
      return(invisible(NULL))
    }
    if (is.null(meta)) {
      meta <- body$meta
      # Keep one random order across pages.
      if (sort == "random" && is.null(query$seed) && !is.null(meta$seed)) {
        query$seed <- format(meta$seed, scientific = FALSE)
      }
    }
    cards <- c(cards, body$data)
    page_count <- as_int(field(body$meta$pagination, "pageCount"))
    if (length(body$data) == 0L || length(cards) >= limit ||
      is.na(page_count) || page >= page_count) {
      break
    }
    page <- page + 1L
  }
  if (length(cards) > limit) cards <- cards[seq_len(limit)]

  attrs <- catalogue_attrs(meta)
  attrs$seed <- if (is.null(query$seed)) NULL else as.numeric(query$seed)
  as_output(parse_spaces(cards, locale), attrs)
}

#' One space from the CoworkingView catalogue, with its prices
#'
#' Fetches a single space by its slug and returns its details together with
#' a pricing table, one row per product the space offers.
#'
#' @param slug Space identifier, as returned in the `slug` column of
#'   [cwv_spaces()].
#' @param locale Language of the titles and URL: `"en"` (default), `"es"`
#'   or `"de"`.
#'
#' @return A list of class `cwv_space` with the elements `slug`, `title`,
#'   `city_slug`, `zone_slug`, `operator_slug`, `operator_name`,
#'   `country_code`, `lat`, `lng`, `featured`, `market_verdict`,
#'   `market_median`, `market_sample_size`, `url` (the listing page),
#'   `updated_at`, `address`, `capacity` (integer, `NA` when unknown),
#'   `amenities` (character vector) and `pricing`, a data frame (a tibble if
#'   \pkg{tibble} is installed) with one row per pricing option:
#'
#'   | Column | Type | Description |
#'   |---|---|---|
#'   | `product` | character | Product, such as `flex_desk`. |
#'   | `title` | character | The operator's name for the option. |
#'   | `price` | double | Price (`NA` when on request). |
#'   | `currency` | character | Currency (`NA` when on request). |
#'   | `billing_period` | character | Billing period, such as `month`, `day`, `hour` or `once`. |
#'   | `price_on_request` | logical | Whether the price is only given on request. |
#'   | `min_capacity`, `max_capacity` | integer | People the option is for (`NA` when absent). |
#'
#'   The list carries the attributes `attribution` and `notice`. A `print()`
#'   method shows a summary. If the API cannot be reached, a message is shown
#'   and `NULL` is returned invisibly; an unknown slug raises a
#'   `cwv_api_error` with `status` 404.
#'
#' @seealso [cwv_spaces()] to find slugs, [cwv_attribution()].
#' @family catalogue
#' @export
#' @examplesIf interactive()
#' space <- cwv_space("sankt-oberholz-rosenthaler-berlin")
#' space
#' space$pricing
cwv_space <- function(slug, locale = "en") {
  if (missing(slug)) {
    cwv_abort("`slug` is required: the identifier of a space, as returned by cwv_spaces().",
      class = "cwv_input_error"
    )
  }
  check_string(slug, "slug", allow_null = FALSE)
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", slug)) {
    cwv_abort(
      sprintf(
        "`slug` must be a space identifier such as \"%s\", not \"%s\".",
        "sankt-oberholz-rosenthaler-berlin", slug
      ),
      class = "cwv_input_error"
    )
  }
  locale <- check_locale(locale)
  path <- paste0("v1/properties/", slug)
  body <- cwv_get(path, list(locale = locale))
  if (is.null(body)) {
    return(invisible(NULL))
  }
  out <- parse_space(body$data, locale)
  attrs <- catalogue_attrs(body$meta)
  out$pricing <- as_output(out$pricing, attrs)
  out <- structure(out, class = "cwv_space")
  for (nm in names(attrs)) attr(out, nm) <- attrs[[nm]]
  out
}

#' @export
print.cwv_space <- function(x, ...) {
  na_or <- function(v, fmt = "%s") if (is.na(v)) "-" else sprintf(fmt, v)
  cat("<cwv_space> ", x$title, "\n", sep = "")
  cat("  Slug:      ", x$slug, "\n", sep = "")
  cat("  Operator:  ", na_or(x$operator_name), "\n", sep = "")
  cat("  Address:   ", na_or(x$address), "\n", sep = "")
  cat("  City/zone: ", na_or(x$city_slug), " / ", na_or(x$zone_slug), "\n",
    sep = ""
  )
  if (!is.na(x$lat) && !is.na(x$lng)) {
    cat("  Location:  ", format(x$lat, digits = 9), ", ",
      format(x$lng, digits = 9), "\n",
      sep = ""
    )
  }
  cat("  Capacity:  ", na_or(x$capacity), "\n", sep = "")
  if (!is.na(x$market_verdict)) {
    cat("  Market:    ", x$market_verdict, " the city median (",
      format(x$market_median), ", n = ", x$market_sample_size, ")\n",
      sep = ""
    )
  }
  if (length(x$amenities)) {
    cat(strwrap(paste(x$amenities, collapse = ", "),
      width = max(getOption("width", 80L) - 2L, 40L),
      initial = "  Amenities: ", prefix = "             "
    ), sep = "\n")
  }
  cat("  URL:       ", x$url, "\n", sep = "")
  pricing <- as.data.frame(x$pricing)
  cat("\nPricing (", nrow(pricing), " option",
    if (nrow(pricing) == 1L) "" else "s", "):\n",
    sep = ""
  )
  if (nrow(pricing)) {
    shown <- data.frame(
      product = pricing$product,
      price = ifelse(
        pricing$price_on_request | is.na(pricing$price),
        "on request",
        paste(vapply(pricing$price, format, ""), pricing$currency)
      ),
      per = pricing$billing_period,
      title = pricing$title,
      stringsAsFactors = FALSE
    )
    print(shown, row.names = FALSE, right = FALSE)
  }
  att <- attr(x, "attribution")
  if (!is.null(att) && !is.na(att)) cat("\n", att, "\n", sep = "")
  invisible(x)
}
