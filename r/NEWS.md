# coworkingview 0.1.0

* First release.
* `cwv_rates()` and `cwv_cities()` return the CoworkingView Price Index
  (CC BY 4.0) as tidy data frames, one row per city and product or per city.
* `cwv_spaces()` searches the catalogue (at most 200 spaces per call) and
  `cwv_space()` returns one space with its pricing table.
* Every result carries its attribution; read it with `cwv_attribution()`.
* Classed errors (`cwv_error`, `cwv_input_error`, `cwv_api_error`), one retry
  on 429 and 5xx, and a message instead of an error when the API cannot be
  reached.
