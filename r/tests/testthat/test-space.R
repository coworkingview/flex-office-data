test_that("cwv_space() pricing matches the golden file", {
  rec <- recording_mock(fixture_response("property_detail.json"))
  httr2::local_mocked_responses(rec$mock)
  space <- cwv_space("sankt-oberholz-rosenthaler-berlin")
  expect_match(
    rec$requests[[1]]$url,
    "/v1/properties/sankt-oberholz-rosenthaler-berlin?locale=en",
    fixed = TRUE
  )
  expect_golden(space$pricing, "space_pricing.csv")
})

test_that("cwv_space() returns the documented fields", {
  httr2::local_mocked_responses(function(req) fixture_response("property_detail.json"))
  space <- cwv_space("sankt-oberholz-rosenthaler-berlin")
  expect_s3_class(space, "cwv_space")
  expect_named(space, c(
    "slug", "title", "city_slug", "zone_slug", "operator_slug",
    "operator_name", "country_code", "lat", "lng", "featured",
    "market_verdict", "market_median", "market_sample_size", "url",
    "updated_at", "address", "capacity", "amenities", "pricing"
  ))
  expect_identical(space$url, "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin")
  expect_identical(space$address, "Rosenthaler Straße 72a, 10119 Berlin, Germany")
  expect_identical(space$capacity, NA_integer_)
  expect_identical(space$zone_slug, "mitte")
  expect_identical(space$lat, 52.5294539)
  expect_true("wifi" %in% space$amenities)
  expect_false(any(c("description", "images") %in% names(space)))
  expect_match(cwv_attribution(space), "St. Oberholz", fixed = TRUE)
  expect_match(cwv_attribution(space$pricing), "St. Oberholz", fixed = TRUE)
  expect_match(cwv_attribution(space, "notice"), "No licence")
})

test_that("print.cwv_space() shows a summary and the pricing table", {
  httr2::local_mocked_responses(function(req) fixture_response("property_detail.json"))
  space <- cwv_space("sankt-oberholz-rosenthaler-berlin")
  out <- capture.output(res <- print(space))
  expect_identical(res, space)
  out <- paste(out, collapse = "\n")
  expect_match(out, "<cwv_space>", fixed = TRUE)
  expect_match(out, "Pricing (5 options)", fixed = TRUE)
  expect_match(out, "209 EUR", fixed = TRUE)
  expect_match(out, "on request", fixed = TRUE)
  expect_match(out, "Source: CoworkingView", fixed = TRUE)
})

test_that("cwv_space() validates its arguments", {
  expect_error(cwv_space(), class = "cwv_input_error")
  expect_error(cwv_space(NA_character_), class = "cwv_input_error")
  expect_error(cwv_space("x", locale = "it"), '"en", "es", "de"', fixed = TRUE)
  expect_error(cwv_space("../admin"), class = "cwv_input_error")
  expect_error(cwv_space("a/b"), "space identifier")
})
