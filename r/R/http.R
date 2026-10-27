# HTTP layer (SPEC section 2). Nothing here runs at load time.

cwv_default_base_url <- "https://api.coworkingview.com"
cwv_version <- "0.1.0"
cwv_max_wait <- 10

cwv_user_agent <- function() {
  sprintf(
    "coworkingview-r/%s (+https://github.com/coworkingview/flex-office-data)",
    cwv_version
  )
}

# Base URL: option `coworkingview.base_url`, then env COWORKINGVIEW_API_URL,
# then the public API.
cwv_base_url <- function() {
  url <- getOption("coworkingview.base_url")
  if (is.null(url) || !nzchar(url)) {
    url <- Sys.getenv("COWORKINGVIEW_API_URL", unset = "")
  }
  if (!nzchar(url)) {
    url <- cwv_default_base_url
  }
  sub("/+$", "", url)
}

cwv_request <- function(path, query = list()) {
  query <- query[!vapply(query, is.null, logical(1))]
  req <- httr2::request(cwv_base_url())
  req <- httr2::req_url_path_append(req, path)
  if (length(query)) {
    req <- do.call(httr2::req_url_query, c(list(req), query))
  }
  req <- httr2::req_user_agent(req, cwv_user_agent())
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_timeout(req, 20)
  # Status handling is done here, not by httr2, so the retry policy and the
  # problem-JSON errors follow the spec exactly.
  httr2::req_error(req, is_error = function(resp) FALSE)
}

# Thin wrappers so tests can replace them with testthat::local_mocked_bindings().
cwv_req_perform <- function(req) httr2::req_perform(req)
cwv_sleep <- function(seconds) Sys.sleep(seconds)

# Perform a request; returns the response, or NULL when the API is unreachable
# (DNS, connection, timeout). Unreachable is reported with a message, not an
# error, following CRAN's policy on internet resources.
cwv_perform <- function(req) {
  tryCatch(
    cwv_req_perform(req),
    httr2_failure = function(e) {
      message(
        "The CoworkingView API could not be reached at ", cwv_base_url(),
        " (", conditionMessage(e), "). ",
        "Check your internet connection or try again later; returning NULL."
      )
      NULL
    }
  )
}

is_retryable <- function(status) status == 429L || status >= 500L

# Seconds to wait before the single retry: Retry-After, else RateLimit-Reset,
# else 2 -- capped at 10.
retry_wait <- function(resp) {
  parse_secs <- function(h) {
    if (is.null(h)) {
      return(NA_real_)
    }
    suppressWarnings(as.numeric(trimws(h)))
  }
  wait <- parse_secs(httr2::resp_header(resp, "Retry-After"))
  if (is.na(wait)) wait <- parse_secs(httr2::resp_header(resp, "RateLimit-Reset"))
  if (is.na(wait)) wait <- 2
  min(max(wait, 0), cwv_max_wait)
}

# GET a path and return the parsed JSON envelope (a list), or NULL when the
# API is unreachable.
cwv_get <- function(path, query = list()) {
  req <- cwv_request(path, query)
  resp <- cwv_perform(req)
  if (is.null(resp)) {
    return(NULL)
  }
  if (is_retryable(httr2::resp_status(resp))) {
    cwv_sleep(retry_wait(resp))
    resp <- cwv_perform(req)
    if (is.null(resp)) {
      return(NULL)
    }
  }
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    cwv_api_abort(resp)
  }
  body <- parse_json_body(resp)
  if (is.null(body) || !is.list(body) || !"data" %in% names(body)) {
    cwv_abort(
      sprintf(
        "CoworkingView API returned a response that is not the expected JSON envelope (HTTP %d).",
        status
      ),
      class = "cwv_api_error",
      status = status, code = "BAD_RESPONSE",
      title = "Bad response", detail = "The response body is not JSON."
    )
  }
  body
}

parse_json_body <- function(resp) {
  if (!httr2::resp_has_body(resp)) {
    return(NULL)
  }
  text <- tryCatch(httr2::resp_body_string(resp, encoding = "UTF-8"),
    error = function(e) NULL
  )
  if (is.null(text)) {
    return(NULL)
  }
  tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

# Turn a non-2xx response into a `cwv_api_error` carrying the RFC 9457
# problem fields (falling back to the HTTP reason phrase).
cwv_api_abort <- function(resp) {
  status <- httr2::resp_status(resp)
  reason <- httr2::resp_status_desc(resp)
  if (is.null(reason) || is.na(reason)) reason <- "HTTP error"
  problem <- parse_json_body(resp)
  if (!is.list(problem)) problem <- list()
  code <- as_chr(problem$code)
  if (is.na(code)) code <- paste0("HTTP_", status)
  title <- as_chr(problem$title %||% reason)
  detail <- as_chr(problem$detail %||% reason)
  msg <- sprintf(
    "CoworkingView API error %d%s: %s",
    status,
    sprintf(" (%s)", code),
    if (identical(title, detail)) title else paste0(title, ". ", detail)
  )
  cwv_abort(
    msg,
    class = "cwv_api_error",
    status = status,
    code = code,
    title = title,
    detail = detail,
    type = as_chr(problem$type),
    errors = problem$errors
  )
}
