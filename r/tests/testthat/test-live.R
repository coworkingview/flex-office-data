# Live tests against the public API. Opt-in only: they run when the
# environment variable COWORKINGVIEW_LIVE_TESTS is "1", never on CRAN, and
# make exactly 3 requests in total.

test_that("live API: rates, spaces and one space (3 requests)", {
  skip_on_cran()
  skip_if_not(
    identical(Sys.getenv("COWORKINGVIEW_LIVE_TESTS"), "1"),
    "Set COWORKINGVIEW_LIVE_TESTS=1 to run live tests"
  )

  rates <- cwv_rates(city = "berlin") # request 1
  expect_s3_class(rates, "data.frame")
  expect_true(nrow(rates) > 0)
  expect_identical(names(rates), names(read_golden("rates.csv")))
  expect_true(all(rates$city_slug == "berlin"))
  expect_match(cwv_attribution(rates), "CC BY 4.0", fixed = TRUE)

  spaces <- cwv_spaces(city = "berlin", limit = 1) # request 2
  expect_identical(nrow(spaces), 1L)
  expect_identical(names(spaces), names(read_golden("spaces.csv")))

  space <- cwv_space(spaces$slug[1]) # request 3
  expect_s3_class(space, "cwv_space")
  expect_identical(space$slug, spaces$slug[1])
  expect_identical(names(space$pricing), names(read_golden("space_pricing.csv")))
})
