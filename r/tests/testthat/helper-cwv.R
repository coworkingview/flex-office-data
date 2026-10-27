# Test helpers. No test in this package touches the network except
# test-live.R, which only runs when COWORKINGVIEW_LIVE_TESTS=1.

fixture_path <- function(name) test_path("fixtures", name)

read_raw <- function(path) readBin(path, "raw", n = file.info(path)$size)

fixture_response <- function(name, status = 200L, headers = list()) {
  httr2::response(
    status_code = status,
    headers = c(list(`Content-Type` = "application/json"), headers),
    body = read_raw(fixture_path(name))
  )
}

text_response <- function(text, status = 200L, headers = list(),
                          type = "application/json") {
  httr2::response(
    status_code = status,
    headers = c(list(`Content-Type` = type), headers),
    body = charToRaw(enc2utf8(text))
  )
}

# Golden CSVs are read as text and compared cell by cell, with the same
# formatting rules as spec/tools/make_golden.py: empty for null,
# true/false for booleans, numbers as the API wrote them.
read_golden <- function(name) {
  lines <- readLines(test_path("golden", name), encoding = "UTF-8", warn = FALSE)
  utils::read.csv(
    text = lines,
    colClasses = "character", na.strings = character(0),
    check.names = FALSE, encoding = "UTF-8"
  )
}

golden_cells <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  out <- lapply(df, function(col) {
    vapply(col, function(v) {
      if (is.na(v)) {
        ""
      } else if (is.logical(v)) {
        if (v) "true" else "false"
      } else if (is.numeric(v)) {
        format(v, digits = 15, scientific = FALSE)
      } else {
        as.character(v)
      }
    }, character(1), USE.NAMES = FALSE)
  })
  out <- as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
  rownames(out) <- NULL
  out
}

expect_golden <- function(df, name) {
  expected <- read_golden(name)
  actual <- golden_cells(df)
  expect_identical(names(actual), names(expected))
  expect_identical(nrow(actual), nrow(expected))
  expect_identical(actual, expected)
}

# A mock that records every request it receives and answers from a list of
# responses (the last one repeats).
recording_mock <- function(...) {
  responses <- list(...)
  env <- new.env()
  env$requests <- list()
  env$mock <- function(req) {
    env$requests[[length(env$requests) + 1L]] <- req
    i <- min(length(env$requests), length(responses))
    responses[[i]]
  }
  env
}

query_of <- function(req) httr2::url_parse(req$url)$query
