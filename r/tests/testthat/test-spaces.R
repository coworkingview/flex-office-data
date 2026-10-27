test_that("cwv_spaces() matches the golden file", {
  httr2::local_mocked_responses(function(req) fixture_response("properties_berlin.json"))
  spaces <- cwv_spaces(city = "berlin", limit = 3)
  expect_golden(spaces, "spaces.csv")
})

test_that("cwv_spaces() returns no images, logos or descriptions", {
  httr2::local_mocked_responses(function(req) fixture_response("properties_berlin.json"))
  spaces <- cwv_spaces(limit = 3)
  expect_false(any(c("images", "logo", "excerpt", "description") %in% names(spaces)))
})

test_that("cwv_spaces() carries the citation and the catalogue notice", {
  httr2::local_mocked_responses(function(req) fixture_response("properties_berlin.json"))
  spaces <- cwv_spaces(city = "berlin", limit = 3)
  expect_match(cwv_attribution(spaces), "Source: CoworkingView", fixed = TRUE)
  expect_match(cwv_attribution(spaces, "notice"), "Systematic extraction")
  expect_identical(attr(spaces, "seed"), 2085917097)
})

test_that("cwv_spaces() maps arguments to the API's query parameters", {
  rec <- recording_mock(fixture_response("properties_berlin.json"))
  httr2::local_mocked_responses(rec$mock)
  cwv_spaces(
    city = "berlin", country = "DE", zone = "mitte", operator = "regus",
    product = "private_office", min_capacity = 4, min_price = 100,
    max_price = 900, currency = "EUR", sort = "price-asc", limit = 3,
    locale = "es"
  )
  q <- query_of(rec$requests[[1]])
  expect_identical(q$city, "berlin")
  expect_identical(q$country, "DE")
  expect_identical(q$zone, "mitte")
  expect_identical(q$operator, "regus")
  expect_identical(q$pricingOptionType, "private_office")
  expect_identical(q$minCapacity, "4")
  expect_identical(q$minPrice, "100")
  expect_identical(q$maxPrice, "900")
  expect_identical(q$currency, "EUR")
  expect_identical(q$sortBy, "price-asc")
  expect_identical(q$page, "1")
  expect_identical(q$pageSize, "3")
  expect_identical(q$locale, "es")
  expect_null(q$seed)
})

test_that("Spanish and German URLs use the localised path", {
  httr2::local_mocked_responses(function(req) fixture_response("properties_berlin.json"))
  expect_match(cwv_spaces(limit = 3, locale = "es")$url[1], "/es/oficina/", fixed = TRUE)
  expect_match(cwv_spaces(limit = 3, locale = "de")$url[1], "/de/buero/", fixed = TRUE)
})

test_that("random order reuses the first page's seed and stops at `limit`", {
  rec <- recording_mock(fixture_response("properties_berlin.json"))
  httr2::local_mocked_responses(rec$mock)
  spaces <- cwv_spaces(city = "berlin", limit = 7)
  # The fixture holds 3 spaces per page: 3 pages, truncated to 7 rows.
  expect_length(rec$requests, 3L)
  expect_identical(nrow(spaces), 7L)
  qs <- lapply(rec$requests, query_of)
  expect_identical(vapply(qs, function(q) q$page, ""), c("1", "2", "3"))
  expect_null(qs[[1]]$seed)
  expect_identical(qs[[2]]$seed, "2085917097")
  expect_identical(qs[[3]]$seed, "2085917097")
  expect_identical(qs[[1]]$pageSize, "7")
})

test_that("pagination stops at pageCount and on an empty page", {
  one_page <- jsonlite::fromJSON(
    fixture_path("properties_berlin.json"), simplifyVector = FALSE
  )
  one_page$meta$pagination$pageCount <- 1L
  rec <- recording_mock(text_response(
    jsonlite::toJSON(one_page, auto_unbox = TRUE, digits = NA, null = "null")
  ))
  httr2::local_mocked_responses(rec$mock)
  expect_identical(nrow(cwv_spaces(limit = 50)), 3L)
  expect_length(rec$requests, 1L)

  rec <- recording_mock(fixture_response("properties_empty.json"))
  httr2::local_mocked_responses(rec$mock)
  empty <- cwv_spaces(city = "nowhere-xyz")
  expect_length(rec$requests, 1L)
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), names(read_golden("spaces.csv")))
  expect_type(empty$lat, "double")
  expect_match(cwv_attribution(empty), "nowhere-xyz")
})

test_that("an explicit seed is sent on every page", {
  rec <- recording_mock(fixture_response("properties_berlin.json"))
  httr2::local_mocked_responses(rec$mock)
  spaces <- cwv_spaces(limit = 4, seed = 42)
  qs <- lapply(rec$requests, query_of)
  expect_identical(vapply(qs, function(q) q$seed, ""), c("42", "42"))
  expect_identical(attr(spaces, "seed"), 42)
})

test_that("non-random sorts send no seed", {
  rec <- recording_mock(fixture_response("properties_berlin.json"))
  httr2::local_mocked_responses(rec$mock)
  cwv_spaces(limit = 4, sort = "date-desc")
  expect_null(query_of(rec$requests[[2]])$seed)
})

test_that("limit is capped at 200, as the catalogue terms require", {
  expect_error(cwv_spaces(limit = 201), class = "cwv_input_error")
  expect_error(cwv_spaces(limit = 1000), "not bulk-copied")
  expect_error(cwv_spaces(limit = 0), class = "cwv_input_error")
  expect_error(cwv_spaces(limit = 2.5), "whole number")
})

test_that("argument errors list the valid values", {
  expect_error(cwv_spaces(product = "desk"), '"flex_desk", "fix_desk"', fixed = TRUE)
  expect_error(
    cwv_spaces(sort = "cheapest"),
    '"random", "price-asc", "date-desc", "date-asc"',
    fixed = TRUE
  )
  expect_error(cwv_spaces(min_capacity = -1), class = "cwv_input_error")
  expect_error(cwv_spaces(max_price = "a"), class = "cwv_input_error")
})
