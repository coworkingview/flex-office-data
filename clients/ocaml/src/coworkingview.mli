(** Client for the public {{:https://coworkingview.com}CoworkingView} API.

    The API needs no key. This library talks to [https://api.coworkingview.com]
    and decodes two resources:

    - [GET /v1/market/rates] — Price Index figures (CC BY 4.0). Every result
      carries the response's attribution.
    - [GET /v1/properties] — paginated catalogue search.

    Operator photos, logos and description text are not decoded. A search that
    follows pages stops at 200 spaces. *)

(** {1 Errors} *)

type field_error = { path : string; message : string }
(** One entry of a problem-JSON [errors] array. *)

type error = {
  status : int;
      (** HTTP status, or [0] when the failure happened before a response. *)
  code : string;
      (** API [code], or [HTTP_<status>], [BAD_RESPONSE], [TIMEOUT],
          [CONNECTION], [INVALID_ARGUMENT]. *)
  title : string option;
  detail : string option;
  type_uri : string option;
      (** Problem-JSON [type] URI, when the body has one. *)
  errors : field_error list;
}
(** Failure of one call. [status] is the HTTP status, not the status copied from
    the body. *)

exception Error of error
(** Raised by every failing call, including validation, connection and HTTP
    errors. Registered with [Printexc]. *)

val string_of_error : error -> string

(** {1 Values shared by both resources} *)

type money = { amount : float; currency : string }
(** A price object: [amount] plus an ISO currency code. The API sends whole
    numbers and decimals; both are read as floats. *)

type place = { slug : string; name : string }
(** A city or neighbourhood reference. *)

type locale =
  | En
  | De
  | Es
      (** [locale] query parameter. The API requires one of [en], [de], [es]. *)

type currency =
  | Eur
  | Gbp
  | Usd
  | Chf
  | Ves
  | Aed
      (** [currency] query parameter. These are the values the API accepts.
          [Ves] is accepted by the parameter list and may still be rejected for
          a given city when no conversion rate exists. *)

type product =
  | Private_office
  | Exclusive_bereich
  | Fix_desk
  | Flex_desk
  | Day_pass
  | Meeting_room
  | Virtual_office
  | Event_space
  | Membership  (** [pricingOptionType] query parameter. *)

type sort =
  | Random
  | Date_desc
  | Date_asc
  | Distance
  | Price_asc
      (** [sortBy] query parameter. Omitted calls leave the API default
          ([random]). *)

(** {1 Price Index} *)

type figure = {
  option_type : string;
  median : money;
  p25 : money;
  p75 : money;
  sample_size : int;
  property_count : int;
  operator_count : int;
  insufficient_data : bool;
}
(** One entry of a city's [figures] array (monthly products). *)

type by_type = {
  option_type : string;
  median : money;
  min : money;
  max : money;
  sample_size : int;
}
(** One entry of a city's [byType] array. *)

type aggregate = {
  median : money;
  sample_size : int;
  property_count : int;
  operator_count : int;
  insufficient_data : bool;
}
(** A [dayPass] or [meetingRoom] object. Only some cities have either. *)

type building = {
  price : money;
  name : string;
  slug : string;
  operator_name : string option;
  operator_slug : string option;
}
(** One entry of [buildings]: the cheapest published monthly option the API
    lists for that space. *)

type city_rates = {
  city : place;
  country_code : string;
  currency : string;
  figures : figure list;
  by_type : by_type list;
  day_pass : aggregate option;
  meeting_room : aggregate option;
  property_count : int;
  operator_count : int;
  insufficient_data : bool;
  p25 : money;
  p75 : money;
  min : money option;
  max : money option;
  entry_median : money;
  entry_min : money;
  entry_max : money;
  buildings : building list;
  sample_size : int;
}
(** One published city in [data.cities]. *)

type unpublished_city = { city : place; insufficient_data : bool option }
(** One entry of [data.unpublished]. The live index currently returns an empty
    array; the record matches the object the API documents for a city below the
    publication threshold. *)

type market_rates = {
  cities : city_rates list;
  unpublished : unpublished_city list;
  total_properties : int;
  total_price_points : int;
  as_of : string;
  license : string;
  license_url : string;
  attribution : string;
  scope : string;
  copyright : string;
  contract_version : string option;
}
(** [GET /v1/market/rates]. [attribution] is the string that must travel with
    any reuse of the Price Index figures. *)

(** {1 Catalogue} *)

type market_position = { verdict : string; median : money; sample_size : int }
(** [marketPosition] on a listing, when the API includes one. *)

type property = {
  slug : string;
  title : string;
  country_code : string;
  city : place;
  zone : place option;
  operator_slug : string;
  operator_name : string;
  lat : float;
  lng : float;
  featured : bool;
  updated_at : string;
  amenities : string list;
  from_price : money option;
  from_billing_period : string option;
  capacity : int option;
  market : market_position option;
}
(** One listing from [GET /v1/properties]. Photos, logos and the [excerpt] are
    not represented. *)

type pagination = { page : int; page_size : int; total : int; page_count : int }

type citation = {
  source : string;
  title : string;
  url : string;
  accessed : string;
  text : string;
}

type properties_page = {
  properties : property list;
  pagination : pagination;
  seed : int64 option;
  citation : citation option;
  catalogue_notice : string option;
  contract_version : string option;
}
(** One page, or the pages concatenated by {!all_properties}. [catalogue_notice]
    is the API's restriction on reuse of the catalogue. *)

(** {1 HTTP} *)

type http_response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

type transport = {
  get : headers:(string * string) list -> string -> http_response Lwt.t;
}
(** One HTTP GET. Raise {!Error} for a connection failure. The default transport
    uses cohttp-lwt-unix. *)

type t
(** A client. It holds no connection pool of its own and performs no I/O until a
    call is made. *)

val version : string
(** Library version, sent in the default [User-Agent]. *)

val make :
  ?base_url:string ->
  ?timeout:float ->
  ?user_agent:string ->
  ?transport:transport ->
  ?sleep:(float -> unit Lwt.t) ->
  unit ->
  t
(** [make ()] talks to [https://api.coworkingview.com].

    [base_url] overrides that default. If omitted, the [COWORKINGVIEW_API_URL]
    environment variable is used when it is set and non-empty. A trailing slash
    is removed.

    [timeout] is the per-request deadline in seconds (default 20). It applies to
    the default transport only.

    [user_agent] defaults to
    [coworkingview-ocaml/<version>
     (+https://github.com/coworkingview/flex-office-data)].

    [transport] and [sleep] replace the HTTP stack and the single retry delay.
    Tests use them so they do not open a socket. On HTTP 429 or 5xx the client
    waits [Retry-After] seconds, else [RateLimit-Reset], else 2 seconds, at most
    10, and tries once more. *)

val base_url : t -> string
val user_agent : t -> string

(** {1 Calls} *)

val market_rates :
  t ->
  ?locale:locale ->
  ?city:string ->
  ?country:string ->
  ?currency:currency ->
  unit ->
  market_rates Lwt.t
(** [GET /v1/market/rates]. [locale] defaults to {!En}. [country] is a slug such
    as ["germany"], not an ISO code. Empty [city] or [country] is rejected. *)

val properties :
  t ->
  ?locale:locale ->
  ?city:string ->
  ?country:string ->
  ?zone:string ->
  ?operator_slug:string ->
  ?product:product ->
  ?min_capacity:int ->
  ?min_price:float ->
  ?max_price:float ->
  ?currency:currency ->
  ?sort:sort ->
  ?page:int ->
  ?page_size:int ->
  ?seed:int64 ->
  unit ->
  properties_page Lwt.t
(** One page of [GET /v1/properties].

    [page] defaults to 1 and must be at least 1. [page_size] defaults to 50,
    which is the maximum the API accepts, and must be between 1 and 50.
    [operator_slug] is sent as [operator]. Other names match the query parameter
    the API documents ([pricingOptionType], [sortBy], [minCapacity], [minPrice],
    [maxPrice], [pageSize]). *)

val all_properties :
  t ->
  ?limit:int ->
  ?locale:locale ->
  ?city:string ->
  ?country:string ->
  ?zone:string ->
  ?operator_slug:string ->
  ?product:product ->
  ?min_capacity:int ->
  ?min_price:float ->
  ?max_price:float ->
  ?currency:currency ->
  ?sort:sort ->
  ?seed:int64 ->
  unit ->
  properties_page Lwt.t
(** Follow pages until [limit] listings have been collected or the catalogue
    page count is exhausted.

    [limit] defaults to 50 and must be between 1 and 200. Each request asks for
    at most 50 rows (the API maximum) and at most the rows still needed. When
    the first page returns a [seed], later pages send it back, which is what the
    API requires for [sort=random]. The returned pagination, citation and
    catalogue notice are those of the first page; [properties] is the
    concatenated list, trimmed to [limit]. *)
