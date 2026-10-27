test_that("requests send the spec's User-Agent, Accept header and timeout", {
  rec <- recording_mock(fixture_response("market_rates.json"))
  httr2::local_mocked_responses(rec$mock)
  cwv_rates()
  req <- rec$requests[[1]]
  expect_identical(
    req$options$useragent,
    "coworkingview-r/0.1.0 (+https://github.com/coworkingview/flex-office-data)"
  )
  expect_identical(req$headers$Accept, "application/json")
  expect_identical(req$options$timeout_ms, 20000)
  expect_match(req$url, "^https://api\\.coworkingview\\.com/v1/market/rates")
})

test_that("the base URL comes from the option, then the environment", {
  rec <- recording_mock(fixture_response("market_rates.json"))
  httr2::local_mocked_responses(rec$mock)

  withr_env <- function(value, code) {
    old <- Sys.getenv("COWORKINGVIEW_API_URL", unset = NA)
    on.exit(if (is.na(old)) Sys.unsetenv("COWORKINGVIEW_API_URL") else Sys.setenv(COWORKINGVIEW_API_URL = old))
    Sys.setenv(COWORKINGVIEW_API_URL = value)
    force(code)
  }
  old_opt <- options(coworkingview.base_url = NULL)
  on.exit(options(old_opt), add = TRUE)

  withr_env("http://localhost:4000/", cwv_rates())
  expect_match(rec$requests[[1]]$url, "^http://localhost:4000/v1/market/rates")

  options(coworkingview.base_url = "http://127.0.0.1:5000")
  withr_env("http://localhost:4000/", cwv_rates())
  expect_match(rec$requests[[2]]$url, "^http://127.0.0.1:5000/v1/market/rates")
})

test_that("problem JSON becomes a classed cwv_api_error", {
  httr2::local_mocked_responses(function(req) {
    fixture_response("error_validation.json", status = 400L,
                     headers = list(`Content-Type` = "application/problem+json"))
  })
  err <- tryCatch(cwv_rates(currency = "VES"), error = identity)
  expect_s3_class(err, "cwv_api_error")
  expect_s3_class(err, "cwv_error")
  expect_identical(err$status, 400L)
  expect_identical(err$code, "VALIDATION_FAILED")
  expect_identical(err$title, "Validation failed")
  expect_match(err$detail, "VES", fixed = TRUE)
  expect_identical(err$errors[[1]]$path, "currency")
  expect_match(conditionMessage(err), "400 (VALIDATION_FAILED)", fixed = TRUE)
})

test_that("a non-JSON error body falls back to the HTTP reason", {
  httr2::local_mocked_responses(function(req) {
    text_response("<html>Not here</html>", status = 404L, type = "text/html")
  })
  err <- tryCatch(cwv_space("missing"), error = identity)
  expect_s3_class(err, "cwv_api_error")
  expect_identical(err$status, 404L)
  expect_identical(err$code, paste0("HTTP_", err$status))
  expect_identical(err$title, "Not Found")
  expect_identical(err$detail, "Not Found")
})

test_that("a non-JSON success body is a BAD_RESPONSE error", {
  httr2::local_mocked_responses(function(req) {
    text_response("<html>maintenance</html>", type = "text/html")
  })
  err <- tryCatch(cwv_cities(), error = identity)
  expect_s3_class(err, "cwv_api_error")
  expect_identical(err$code, "BAD_RESPONSE")
  expect_identical(err$status, 200L)
})

test_that("429 and 5xx are retried once after Retry-After", {
  waits <- c()
  local_mocked_bindings(cwv_sleep = function(seconds) waits <<- c(waits, seconds))
  rec <- recording_mock(
    text_response("{}", status = 503L, headers = list(`Retry-After` = "3")),
    fixture_response("market_rates.json")
  )
  httr2::local_mocked_responses(rec$mock)
  rates <- cwv_rates()
  expect_length(rec$requests, 2L)
  expect_identical(waits, 3)
  expect_identical(nrow(rates), 13L)
})

test_that("the retry happens only once and the wait is capped at 10 s", {
  waits <- c()
  local_mocked_bindings(cwv_sleep = function(seconds) waits <<- c(waits, seconds))
  rec <- recording_mock(text_response(
    '{"title":"Too Many Requests","status":429,"code":"RATE_LIMITED","detail":"Slow down."}',
    status = 429L, headers = list(`Retry-After` = "120")
  ))
  httr2::local_mocked_responses(rec$mock)
  err <- tryCatch(cwv_rates(), error = identity)
  expect_length(rec$requests, 2L)
  expect_identical(waits, 10)
  expect_s3_class(err, "cwv_api_error")
  expect_identical(err$status, 429L)
  expect_identical(err$code, "RATE_LIMITED")
})

test_that("the wait falls back to RateLimit-Reset, then 2 s", {
  waits <- c()
  local_mocked_bindings(cwv_sleep = function(seconds) waits <<- c(waits, seconds))
  httr2::local_mocked_responses(recording_mock(
    text_response("{}", status = 500L, headers = list(`RateLimit-Reset` = "7")),
    fixture_response("market_rates.json")
  )$mock)
  cwv_rates()
  httr2::local_mocked_responses(recording_mock(
    text_response("{}", status = 502L),
    fixture_response("market_rates.json")
  )$mock)
  cwv_rates()
  expect_identical(waits, c(7, 2))
})

test_that("other 4xx statuses are not retried", {
  local_mocked_bindings(cwv_sleep = function(seconds) stop("should not sleep"))
  rec <- recording_mock(fixture_response("error_validation.json", status = 400L))
  httr2::local_mocked_responses(rec$mock)
  expect_error(cwv_rates(), class = "cwv_api_error")
  expect_length(rec$requests, 1L)
})

test_that("an unreachable API gives a message and NULL, not an error", {
  local_mocked_bindings(cwv_req_perform = function(req) {
    stop(structure(
      class = c("httr2_failure", "httr2_error", "rlang_error", "error", "condition"),
      list(message = "Could not resolve host: api.coworkingview.com", call = NULL)
    ))
  })
  expect_message(res <- cwv_rates(), "could not be reached")
  expect_null(res)
  expect_message(res <- cwv_spaces(), "could not be reached")
  expect_null(res)
  expect_message(res <- cwv_space("x"), "could not be reached")
  expect_null(res)
  expect_null(cwv_attribution(res))
})
