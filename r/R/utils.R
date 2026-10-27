# Internal helpers: conditions, argument checks, scalar extraction, output.

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- conditions --------------------------------------------------------------

# Signal a classed error. Every error raised by the package inherits from
# `cwv_error`; API failures additionally inherit from `cwv_api_error`.
cwv_abort <- function(message, class = NULL, ..., call = NULL) {
  cnd <- structure(
    class = c(class, "cwv_error", "error", "condition"),
    list(message = message, call = call, ...)
  )
  stop(cnd)
}

# ---- argument checks ---------------------------------------------------------

quote_values <- function(x) paste0("\"", x, "\"", collapse = ", ")

check_string <- function(x, arg, allow_null = TRUE) {
  if (is.null(x) && allow_null) {
    return(invisible(NULL))
  }
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    cwv_abort(
      sprintf("`%s` must be a single non-empty string.", arg),
      class = "cwv_input_error"
    )
  }
  invisible(x)
}

# match.arg()-style check that lists the valid values in the error message.
check_choice <- function(x, choices, arg, allow_null = TRUE) {
  if (is.null(x) && allow_null) {
    return(NULL)
  }
  check_string(x, arg, allow_null = FALSE)
  if (!x %in% choices) {
    cwv_abort(
      sprintf(
        "`%s` must be one of %s, not \"%s\".",
        arg, quote_values(choices), x
      ),
      class = "cwv_input_error"
    )
  }
  x
}

check_number <- function(x, arg, min = -Inf, whole = FALSE) {
  if (is.null(x)) {
    return(NULL)
  }
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x >= min && (!whole || x == round(x))
  if (!ok) {
    what <- if (whole) "a single whole number" else "a single number"
    if (is.finite(min)) what <- sprintf("%s >= %s", what, format(min))
    cwv_abort(sprintf("`%s` must be %s.", arg, what), class = "cwv_input_error")
  }
  x
}

# ---- accepted values (SPEC section 1) ----------------------------------------

cwv_locales <- c("en", "es", "de")
cwv_currencies <- c("EUR", "GBP", "USD", "CHF", "AED", "VES")
cwv_products <- c(
  "flex_desk", "fix_desk", "private_office", "exclusive_bereich",
  "day_pass", "meeting_room", "event_space", "virtual_office", "membership"
)
cwv_sorts <- c("random", "price-asc", "date-desc", "date-asc")

check_locale <- function(locale) {
  check_choice(locale, cwv_locales, "locale", allow_null = FALSE)
}

check_currency <- function(currency) {
  if (is.null(currency)) {
    return(NULL)
  }
  check_string(currency, "currency", allow_null = FALSE)
  check_choice(toupper(currency), cwv_currencies, "currency")
}

# ---- scalar extraction from parsed JSON (NULL -> typed NA) -------------------

as_chr <- function(x) {
  if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[[1L]])
}
as_num <- function(x) {
  if (is.null(x) || length(x) == 0L) NA_real_ else as.numeric(x[[1L]])
}
as_int <- function(x) {
  if (is.null(x) || length(x) == 0L) NA_integer_ else as.integer(x[[1L]])
}
as_lgl <- function(x) {
  if (is.null(x) || length(x) == 0L) NA else as.logical(x[[1L]])
}
amount <- function(money) {
  if (is.list(money)) as_num(money$amount) else NA_real_
}
field <- function(x, name) if (is.list(x)) x[[name]] else NULL

# Build a data frame from a list of row lists, with a fixed column template so
# zero-row results still carry the right columns and types.
rows_to_df <- function(rows, template) {
  cols <- lapply(names(template), function(col) {
    proto <- template[[col]]
    if (length(rows) == 0L) {
      return(proto[0L])
    }
    vapply(rows, function(r) r[[col]], proto[1L], USE.NAMES = FALSE)
  })
  names(cols) <- names(template)
  df <- as.data.frame(cols, stringsAsFactors = FALSE, optional = TRUE)
  rownames(df) <- NULL
  df
}

# Return a tibble when tibble is installed, else the base data frame. Custom
# attributes are re-applied after the conversion.
as_output <- function(df, attrs = list()) {
  if (requireNamespace("tibble", quietly = TRUE)) {
    df <- tibble::as_tibble(df)
  }
  for (nm in names(attrs)) {
    if (!is.null(attrs[[nm]])) attr(df, nm) <- attrs[[nm]]
  }
  df
}
