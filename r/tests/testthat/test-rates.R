test_that("cwv_rates() matches the golden file", {
  httr2::local_mocked_responses(function(req) fixture_response("market_rates.json"))
  rates <- cwv_rates()
  expect_s3_class(rates, "data.frame")
  expect_golden(rates, "rates.csv")
})

test_that("cwv_rates() columns have the documented types", {
  httr2::local_mocked_responses(function(req) fixture_response("market_rates.json"))
  rates <- cwv_rates()
  types <- vapply(rates, typeof, character(1))
  expect_identical(types, c(
    city_slug = "character", city_name = "character",
    country_code = "character", currency = "character",
    product = "character", unit = "character",
    median = "double", p25 = "double", p75 = "double",
    sample_size = "integer", property_count = "integer",
    operator_count = "integer", low_confidence = "logical",
    as_of = "character"
  ))
})

test_that("cwv_rates() carries the CC BY 4.0 attribution", {
  httr2::local_mocked_responses(function(req) fixture_response("market_rates.json"))
  rates <- cwv_rates()
  expect_match(attr(rates, "attribution"), "CC BY 4.0", fixed = TRUE)
  expect_identical(
    attr(rates, "license"),
    "https://creativecommons.org/licenses/by/4.0/"
  )
  expect_identical(attr(rates, "as_of"), "2026-10-27T21:06:48.313Z")
  expect_identical(cwv_attribution(rates), attr(rates, "attribution"))
  expect_identical(cwv_attribution(rates, "as_of"), "2026-10-27T21:06:48.313Z")
  expect_null(cwv_attribution(rates, "notice"))
})

test_that("cwv_rates() sends filters as query parameters", {
  rec <- recording_mock(fixture_response("market_rates_berlin_usd.json"))
  httr2::local_mocked_responses(rec$mock)
  rates <- cwv_rates(city = "berlin", currency = "usd", locale = "de")
  q <- query_of(rec$requests[[1]])
  expect_identical(q$city, "berlin")
  expect_identical(q$currency, "USD")
  expect_identical(q$locale, "de")
  expect_null(q$country)
  expect_match(rec$requests[[1]]$url, "/v1/market/rates?", fixed = TRUE)
  expect_true(all(rates$currency == "USD"))
  expect_true(all(rates$city_slug == "berlin"))
  expect_identical(
    rates$product,
    c("flex_desk", "fix_desk", "private_office", "day_pass", "meeting_room")
  )
})

test_that("byType is used when figures is absent, and unknown aggregates appear", {
  data <- list(
    asOf = "2026-01-01T00:00:00Z",
    attribution = "x", licenseUrl = "y",
    cities = list(list(
      city = list(slug = "zz", name = "Zed"),
      countryCode = "XX",
      currency = "EUR",
      byType = list(list(
        optionType = "flex_desk",
        median = list(amount = 100, currency = "EUR"),
        sampleSize = 12
      )),
      eventSpace = list(
        median = list(amount = 80, currency = "EUR"),
        p25 = list(amount = 60, currency = "EUR"),
        sampleSize = 4
      ),
      rooftopBar = list(
        median = list(amount = 9, currency = "EUR"),
        sampleSize = 30
      )
    ))
  )
  body <- jsonlite::toJSON(list(data = data, meta = list()), auto_unbox = TRUE)
  httr2::local_mocked_responses(function(req) text_response(body))
  rates <- cwv_rates()
  expect_identical(rates$product, c("flex_desk", "event_space", "rooftop_bar"))
  expect_identical(rates$unit, c("month", "hour", NA))
  expect_identical(rates$p25, c(NA, 60, NA))
  expect_identical(rates$low_confidence, c(FALSE, TRUE, FALSE))
})

test_that("cwv_cities() matches the golden file", {
  httr2::local_mocked_responses(function(req) fixture_response("market_rates.json"))
  cities <- cwv_cities()
  expect_golden(cities, "cities.csv")
  expect_identical(cities$published, c(TRUE, TRUE, TRUE, FALSE))
  expect_match(cwv_attribution(cities), "CoworkingView Price Index")
})

test_that("argument errors list the valid values", {
  expect_error(cwv_rates(currency = "JPY"), class = "cwv_input_error")
  expect_error(
    cwv_rates(currency = "JPY"),
    '"EUR", "GBP", "USD", "CHF", "AED", "VES"',
    fixed = TRUE
  )
  expect_error(cwv_rates(locale = "fr"), '"en", "es", "de"', fixed = TRUE)
  expect_error(cwv_rates(city = c("a", "b")), class = "cwv_error")
  expect_error(cwv_cities(country = 1), "single non-empty string")
})
