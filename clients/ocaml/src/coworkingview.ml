type field_error = { path : string; message : string }

type error = {
  status : int;
  code : string;
  title : string option;
  detail : string option;
  type_uri : string option;
  errors : field_error list;
}

exception Error of error

let string_of_error e =
  let title = Option.value e.title ~default:"" in
  let detail = match e.detail with None -> "" | Some d -> ": " ^ d in
  Printf.sprintf "Coworkingview.Error %s (status %d) %s%s" e.code e.status title
    detail

let () =
  Printexc.register_printer (function
    | Error e -> Some (string_of_error e)
    | _ -> None)

type money = { amount : float; currency : string }
type place = { slug : string; name : string }
type locale = En | De | Es
type currency = Eur | Gbp | Usd | Chf | Ves | Aed

type product =
  | Private_office
  | Exclusive_bereich
  | Fix_desk
  | Flex_desk
  | Day_pass
  | Meeting_room
  | Virtual_office
  | Event_space
  | Membership

type sort = Random | Date_desc | Date_asc | Distance | Price_asc

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

type by_type = {
  option_type : string;
  median : money;
  min : money;
  max : money;
  sample_size : int;
}

type aggregate = {
  median : money;
  sample_size : int;
  property_count : int;
  operator_count : int;
  insufficient_data : bool;
}

type building = {
  price : money;
  name : string;
  slug : string;
  operator_name : string option;
  operator_slug : string option;
}

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

type unpublished_city = { city : place; insufficient_data : bool option }

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

type market_position = { verdict : string; median : money; sample_size : int }

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

type http_response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

type transport = {
  get : headers:(string * string) list -> string -> http_response Lwt.t;
}

let version = "0.1.0"
let default_base_url = "https://api.coworkingview.com"

let default_user_agent =
  "coworkingview-ocaml/" ^ version
  ^ " (+https://github.com/coworkingview/flex-office-data)"

module R = struct
  type ('a, 'e) t = Ok of 'a | Error of 'e

  let bind x f = match x with Ok v -> f v | Error _ as e -> e
end

module Parse = struct
  let ( let* ) = R.bind
  let err fmt = Printf.ksprintf (fun s -> R.Error s) fmt
  let field name = function `Assoc fs -> List.assoc_opt name fs | _ -> None

  let required name json =
    match field name json with
    | None | Some `Null -> err "missing %s" name
    | Some v -> R.Ok v

  let string name json =
    match required name json with
    | R.Error _ as e -> e
    | R.Ok (`String s) -> R.Ok s
    | R.Ok _ -> err "%s is not a string" name

  let opt_string name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some (`String s) -> R.Ok (Some s)
    | Some _ -> err "%s is not a string" name

  let bool name json =
    match required name json with
    | R.Error _ as e -> e
    | R.Ok (`Bool b) -> R.Ok b
    | R.Ok _ -> err "%s is not a bool" name

  let opt_bool name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some (`Bool b) -> R.Ok (Some b)
    | Some _ -> err "%s is not a bool" name

  let int name json =
    match required name json with
    | R.Error _ as e -> e
    | R.Ok (`Int i) -> R.Ok i
    | R.Ok (`Intlit s) -> (
        match int_of_string_opt s with
        | Some i -> R.Ok i
        | None -> err "%s is not an int" name)
    | R.Ok _ -> err "%s is not an int" name

  let opt_int name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some (`Int i) -> R.Ok (Some i)
    | Some (`Intlit s) -> (
        match int_of_string_opt s with
        | Some i -> R.Ok (Some i)
        | None -> err "%s is not an int" name)
    | Some _ -> err "%s is not an int" name

  let int64 name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some (`Int i) -> R.Ok (Some (Int64.of_int i))
    | Some (`Intlit s) -> (
        match Int64.of_string_opt s with
        | Some i -> R.Ok (Some i)
        | None -> err "%s is not an int" name)
    | Some _ -> err "%s is not an int" name

  let float_of name json =
    match json with
    | `Int i -> R.Ok (float_of_int i)
    | `Intlit s -> (
        match float_of_string_opt s with
        | Some f -> R.Ok f
        | None -> err "%s is not a number" name)
    | `Float f -> R.Ok f
    | _ -> err "%s is not a number" name

  let money json =
    let* amount =
      match required "amount" json with
      | R.Error _ as e -> e
      | R.Ok v -> float_of "amount" v
    in
    let* currency = string "currency" json in
    R.Ok { amount; currency }

  let opt_money name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some v -> (
        match money v with
        | R.Ok m -> R.Ok (Some m)
        | R.Error e -> err "%s: %s" name e)

  let money_field name json =
    match required name json with
    | R.Error _ as e -> e
    | R.Ok v -> (
        match money v with R.Ok m -> R.Ok m | R.Error e -> err "%s: %s" name e)

  let place json =
    let* slug = string "slug" json in
    let* name = string "name" json in
    R.Ok { slug; name }

  let place_field name json =
    match required name json with
    | R.Error _ as e -> e
    | R.Ok v -> (
        match place v with R.Ok p -> R.Ok p | R.Error e -> err "%s: %s" name e)

  let opt_place name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some v -> (
        match place v with
        | R.Ok p -> R.Ok (Some p)
        | R.Error e -> err "%s: %s" name e)

  let list_of name parse json =
    match required name json with
    | R.Error _ as e -> e
    | R.Ok (`List items) ->
        let rec loop acc = function
          | [] -> R.Ok (List.rev acc)
          | item :: rest -> (
              match parse item with
              | R.Ok v -> loop (v :: acc) rest
              | R.Error e -> err "%s: %s" name e)
        in
        loop [] items
    | R.Ok _ -> err "%s is not a list" name

  let string_list name json =
    list_of name (function `String s -> R.Ok s | _ -> err "not a string") json

  let figure json =
    let* option_type = string "optionType" json in
    let* median = money_field "median" json in
    let* p25 = money_field "p25" json in
    let* p75 = money_field "p75" json in
    let* sample_size = int "sampleSize" json in
    let* property_count = int "propertyCount" json in
    let* operator_count = int "operatorCount" json in
    let* insufficient_data = bool "insufficientData" json in
    R.Ok
      {
        option_type;
        median;
        p25;
        p75;
        sample_size;
        property_count;
        operator_count;
        insufficient_data;
      }

  let by_type json =
    let* option_type = string "optionType" json in
    let* median = money_field "median" json in
    let* min = money_field "min" json in
    let* max = money_field "max" json in
    let* sample_size = int "sampleSize" json in
    R.Ok { option_type; median; min; max; sample_size }

  let aggregate json =
    let* median = money_field "median" json in
    let* sample_size = int "sampleSize" json in
    let* property_count = int "propertyCount" json in
    let* operator_count = int "operatorCount" json in
    let* insufficient_data = bool "insufficientData" json in
    R.Ok
      { median; sample_size; property_count; operator_count; insufficient_data }

  let opt_aggregate name json =
    match field name json with
    | None | Some `Null -> R.Ok None
    | Some v -> (
        match aggregate v with
        | R.Ok a -> R.Ok (Some a)
        | R.Error e -> err "%s: %s" name e)

  let building json =
    let* price = money_field "price" json in
    let* name = string "name" json in
    let* slug = string "slug" json in
    let* operator_name = opt_string "operatorName" json in
    let* operator_slug = opt_string "operatorSlug" json in
    R.Ok { price; name; slug; operator_name; operator_slug }

  let city json =
    let* city = place_field "city" json in
    let* country_code = string "countryCode" json in
    let* currency = string "currency" json in
    let* figures = list_of "figures" figure json in
    let* by_type = list_of "byType" by_type json in
    let* day_pass = opt_aggregate "dayPass" json in
    let* meeting_room = opt_aggregate "meetingRoom" json in
    let* property_count = int "propertyCount" json in
    let* operator_count = int "operatorCount" json in
    let* insufficient_data = bool "insufficientData" json in
    let* p25 = money_field "p25" json in
    let* p75 = money_field "p75" json in
    let* min = opt_money "min" json in
    let* max = opt_money "max" json in
    let* entry_median = money_field "entryMedian" json in
    let* entry_min = money_field "entryMin" json in
    let* entry_max = money_field "entryMax" json in
    let* buildings = list_of "buildings" building json in
    let* sample_size = int "sampleSize" json in
    R.Ok
      {
        city;
        country_code;
        currency;
        figures;
        by_type;
        day_pass;
        meeting_room;
        property_count;
        operator_count;
        insufficient_data;
        p25;
        p75;
        min;
        max;
        entry_median;
        entry_min;
        entry_max;
        buildings;
        sample_size;
      }

  let unpublished json =
    let* city = place_field "city" json in
    let* insufficient_data = opt_bool "insufficientData" json in
    R.Ok { city; insufficient_data }

  let contract_version json =
    match field "meta" json with
    | Some meta -> opt_string "contractVersion" meta
    | None -> R.Ok None

  let market json =
    match field "data" json with
    | None -> err "response has no data member"
    | Some data ->
        let* cities = list_of "cities" city data in
        let* unpublished = list_of "unpublished" unpublished data in
        let* total_properties = int "totalProperties" data in
        let* total_price_points = int "totalPricePoints" data in
        let* as_of = string "asOf" data in
        let* license = string "license" data in
        let* license_url = string "licenseUrl" data in
        let* attribution = string "attribution" data in
        let* scope = string "scope" data in
        let* copyright = string "copyright" data in
        let* contract_version = contract_version json in
        R.Ok
          {
            cities;
            unpublished;
            total_properties;
            total_price_points;
            as_of;
            license;
            license_url;
            attribution;
            scope;
            copyright;
            contract_version;
          }

  let market_position json =
    let* verdict = string "verdict" json in
    let* median = money_field "median" json in
    let* sample_size = int "sampleSize" json in
    R.Ok { verdict; median; sample_size }

  let property json =
    let* slug = string "slug" json in
    let* title = string "title" json in
    let* country_code = string "countryCode" json in
    let* city = place_field "city" json in
    let* zone = opt_place "zone" json in
    let* operator =
      match required "operator" json with
      | R.Error _ as e -> e
      | R.Ok v -> R.Ok v
    in
    let* operator_slug = string "slug" operator in
    let* operator_name = string "name" operator in
    let* coordinates = required "coordinates" json in
    let* lat =
      match required "lat" coordinates with
      | R.Error _ as e -> e
      | R.Ok v -> float_of "lat" v
    in
    let* lng =
      match required "lng" coordinates with
      | R.Error _ as e -> e
      | R.Ok v -> float_of "lng" v
    in
    let* featured = bool "featured" json in
    let* updated_at = string "updatedAt" json in
    let* amenities = string_list "amenities" json in
    let* from_price = opt_money "fromPrice" json in
    let* from_billing_period = opt_string "fromBillingPeriod" json in
    let* capacity = opt_int "capacity" json in
    let* market =
      match field "marketPosition" json with
      | None | Some `Null -> R.Ok None
      | Some v -> (
          match market_position v with
          | R.Ok m -> R.Ok (Some m)
          | R.Error e -> err "marketPosition: %s" e)
    in
    R.Ok
      {
        slug;
        title;
        country_code;
        city;
        zone;
        operator_slug;
        operator_name;
        lat;
        lng;
        featured;
        updated_at;
        amenities;
        from_price;
        from_billing_period;
        capacity;
        market;
      }

  let pagination json =
    let* page = int "page" json in
    let* page_size = int "pageSize" json in
    let* total = int "total" json in
    let* page_count = int "pageCount" json in
    R.Ok { page; page_size; total; page_count }

  let citation json =
    let* source = string "source" json in
    let* title = string "title" json in
    let* url = string "url" json in
    let* accessed = string "accessed" json in
    let* text = string "text" json in
    R.Ok { source; title; url; accessed; text }

  let opt_citation meta =
    match field "citation" meta with
    | None | Some `Null -> R.Ok None
    | Some v -> (
        match citation v with
        | R.Ok c -> R.Ok (Some c)
        | R.Error e -> err "citation: %s" e)

  let properties json =
    match field "data" json with
    | None -> err "response has no data member"
    | Some (`List _) as data -> (
        let* properties =
          list_of "data" property (`Assoc [ ("data", Option.get data) ])
        in
        match field "meta" json with
        | None -> err "response has no meta member"
        | Some meta ->
            let* pagination =
              match required "pagination" meta with
              | R.Error _ as e -> e
              | R.Ok v -> pagination v
            in
            let* seed = int64 "seed" meta in
            let* citation = opt_citation meta in
            let* catalogue_notice = opt_string "catalogueNotice" meta in
            let* contract_version = opt_string "contractVersion" meta in
            R.Ok
              {
                properties;
                pagination;
                seed;
                citation;
                catalogue_notice;
                contract_version;
              })
    | Some _ -> err "data is not a list"

  let field_errors json =
    match json with
    | `List items ->
        List.map
          (fun item ->
            let path =
              match field "path" item with Some (`String s) -> s | _ -> ""
            in
            let message =
              match field "message" item with Some (`String s) -> s | _ -> ""
            in
            { path; message })
          items
    | _ -> []

  let of_string body =
    match Yojson.Safe.from_string body with
    | json -> R.Ok json
    | exception Yojson.Json_error msg -> err "%s" msg
end

type t = {
  base_url : string;
  user_agent : string;
  transport : transport;
  sleep : float -> unit Lwt.t;
}

let invalid detail =
  {
    status = 0;
    code = "INVALID_ARGUMENT";
    title = Some "Invalid argument";
    detail = Some detail;
    type_uri = None;
    errors = [];
  }

let bad_response detail =
  {
    status = 200;
    code = "BAD_RESPONSE";
    title = Some "Unexpected response";
    detail = Some detail;
    type_uri = None;
    errors = [];
  }

let connection_error exn =
  {
    status = 0;
    code = "CONNECTION";
    title = Some "Connection failed";
    detail = Some (Printexc.to_string exn);
    type_uri = None;
    errors = [];
  }

let nonempty name = function
  | None -> None
  | Some s ->
      let s = String.trim s in
      if s = "" then raise (Error (invalid (name ^ " must not be empty")))
      else Some s

let locale_to_string = function En -> "en" | De -> "de" | Es -> "es"

let currency_to_string = function
  | Eur -> "EUR"
  | Gbp -> "GBP"
  | Usd -> "USD"
  | Chf -> "CHF"
  | Ves -> "VES"
  | Aed -> "AED"

let product_to_string = function
  | Private_office -> "private_office"
  | Exclusive_bereich -> "exclusive_bereich"
  | Fix_desk -> "fix_desk"
  | Flex_desk -> "flex_desk"
  | Day_pass -> "day_pass"
  | Meeting_room -> "meeting_room"
  | Virtual_office -> "virtual_office"
  | Event_space -> "event_space"
  | Membership -> "membership"

let sort_to_string = function
  | Random -> "random"
  | Date_desc -> "date-desc"
  | Date_asc -> "date-asc"
  | Distance -> "distance"
  | Price_asc -> "price-asc"

let string_of_query_float x =
  if classify_float x <> FP_normal && classify_float x <> FP_zero then
    raise (Error (invalid "price must be a finite number"));
  let s = Printf.sprintf "%.6f" x in
  let rec strip i =
    if i > 0 && s.[i] = '0' then strip (i - 1)
    else if i > 0 && s.[i] = '.' then i - 1
    else i
  in
  let last = strip (String.length s - 1) in
  String.sub s 0 (last + 1)

let add name value pairs =
  match value with None -> pairs | Some v -> (name, v) :: pairs

let header_value headers name =
  let name = String.lowercase_ascii name in
  let rec loop = function
    | [] -> None
    | (key, value) :: rest ->
        if String.lowercase_ascii (String.trim key) = name then
          Some (String.trim value)
        else loop rest
  in
  loop headers

let seconds_header headers name =
  match header_value headers name with
  | None -> None
  | Some s -> float_of_string_opt s

let retry_delay headers =
  let raw =
    match seconds_header headers "retry-after" with
    | Some s -> s
    | None -> (
        match seconds_header headers "ratelimit-reset" with
        | Some s -> s
        | None -> 2.)
  in
  let raw = if raw < 0. then 0. else raw in
  if raw > 10. then 10. else raw

let retryable status = status = 429 || (status >= 500 && status <= 599)

let problem_of response =
  let title_fallback = Cohttp.Code.reason_phrase_of_code response.status in
  match Parse.of_string response.body with
  | R.Error _ ->
      {
        status = response.status;
        code = Printf.sprintf "HTTP_%d" response.status;
        title = Some title_fallback;
        detail = None;
        type_uri = None;
        errors = [];
      }
  | R.Ok json ->
      let code =
        match Parse.field "code" json with
        | Some (`String s) when s <> "" -> s
        | _ -> Printf.sprintf "HTTP_%d" response.status
      in
      let title =
        match Parse.field "title" json with
        | Some (`String s) when s <> "" -> Some s
        | _ -> Some title_fallback
      in
      let detail =
        match Parse.field "detail" json with
        | Some (`String s) -> Some s
        | _ -> None
      in
      let type_uri =
        match Parse.field "type" json with
        | Some (`String s) -> Some s
        | _ -> None
      in
      let errors =
        match Parse.field "errors" json with
        | Some v -> Parse.field_errors v
        | None -> []
      in
      { status = response.status; code; title; detail; type_uri; errors }

let default_transport ~timeout =
  let get ~headers url =
    let header = Cohttp.Header.of_list headers in
    Lwt.catch
      (fun () ->
        Lwt_unix.with_timeout timeout (fun () ->
            let open Lwt.Syntax in
            let* resp, body =
              Cohttp_lwt_unix.Client.get ~headers:header (Uri.of_string url)
            in
            let status =
              Cohttp.Code.code_of_status (Cohttp.Response.status resp)
            in
            let headers =
              Cohttp.Header.to_list (Cohttp.Response.headers resp)
            in
            let* body = Cohttp_lwt.Body.to_string body in
            Lwt.return { status; headers; body }))
      (function
        | Lwt_unix.Timeout ->
            Lwt.fail
              (Error
                 {
                   status = 0;
                   code = "TIMEOUT";
                   title = Some "Request timed out";
                   detail =
                     Some
                       (Printf.sprintf "No response within %.0f seconds" timeout);
                   type_uri = None;
                   errors = [];
                 })
        | Error _ as exn -> Lwt.fail exn
        | exn -> Lwt.fail (Error (connection_error exn)))
  in
  { get }

let strip_trailing_slash s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '/' then String.sub s 0 (n - 1) else s

let make ?base_url ?(timeout = 20.) ?user_agent ?transport ?sleep () =
  if timeout <= 0. then
    raise (Invalid_argument "Coworkingview.make: timeout must be positive");
  let base_url =
    match base_url with
    | Some u -> u
    | None -> (
        match Sys.getenv_opt "COWORKINGVIEW_API_URL" with
        | Some u when String.trim u <> "" -> u
        | _ -> default_base_url)
  in
  let base_url = strip_trailing_slash (String.trim base_url) in
  if base_url = "" then raise (Error (invalid "base_url must not be empty"));
  let user_agent =
    match user_agent with Some ua -> ua | None -> default_user_agent
  in
  let transport =
    match transport with Some t -> t | None -> default_transport ~timeout
  in
  let sleep = match sleep with Some s -> s | None -> Lwt_unix.sleep in
  { base_url; user_agent; transport; sleep }

let base_url t = t.base_url
let user_agent t = t.user_agent

let request_headers t =
  [ ("User-Agent", t.user_agent); ("Accept", "application/json") ]

let endpoint t path query =
  let uri = Uri.with_query' (Uri.of_string (t.base_url ^ path)) query in
  Uri.to_string uri

open Lwt.Syntax

let perform t url =
  let headers = request_headers t in
  let rec attempt n =
    let* response =
      Lwt.catch
        (fun () -> t.transport.get ~headers url)
        (function
          | Error _ as exn -> Lwt.fail exn
          | exn -> Lwt.fail (Error (connection_error exn)))
    in
    if retryable response.status && n = 0 then
      let* () = t.sleep (retry_delay response.headers) in
      attempt 1
    else if response.status < 200 || response.status >= 300 then
      Lwt.fail (Error (problem_of response))
    else Lwt.return response.body
  in
  attempt 0

let decode parse body =
  match Parse.of_string body with
  | R.Error msg -> Lwt.fail (Error (bad_response msg))
  | R.Ok json -> (
      match parse json with
      | R.Ok v -> Lwt.return v
      | R.Error msg -> Lwt.fail (Error (bad_response msg)))

let market_rates t ?(locale = En) ?city ?country ?currency () =
  let city = nonempty "city" city in
  let country = nonempty "country" country in
  let query =
    [ ("locale", locale_to_string locale) ]
    |> add "city" city |> add "country" country
    |> add "currency" (Option.map currency_to_string currency)
  in
  let* body = perform t (endpoint t "/v1/market/rates" query) in
  decode Parse.market body

let check_page page =
  if page < 1 then raise (Error (invalid "page must be >= 1"))

let check_page_size page_size =
  if page_size < 1 || page_size > 50 then
    raise (Error (invalid "page_size must be between 1 and 50"))

let properties t ?(locale = En) ?city ?country ?zone ?operator_slug ?product
    ?min_capacity ?min_price ?max_price ?currency ?sort ?(page = 1)
    ?(page_size = 50) ?seed () =
  check_page page;
  check_page_size page_size;
  let city = nonempty "city" city in
  let country = nonempty "country" country in
  let zone = nonempty "zone" zone in
  let operator_slug = nonempty "operator" operator_slug in
  if min_capacity <> None && Option.get min_capacity < 0 then
    raise (Error (invalid "min_capacity must be >= 0"));
  let query =
    [ ("locale", locale_to_string locale) ]
    |> add "city" city |> add "country" country |> add "zone" zone
    |> add "operator" operator_slug
    |> add "pricingOptionType" (Option.map product_to_string product)
    |> add "minCapacity" (Option.map string_of_int min_capacity)
    |> add "minPrice" (Option.map string_of_query_float min_price)
    |> add "maxPrice" (Option.map string_of_query_float max_price)
    |> add "currency" (Option.map currency_to_string currency)
    |> add "sortBy" (Option.map sort_to_string sort)
    |> add "page" (Some (string_of_int page))
    |> add "pageSize" (Some (string_of_int page_size))
    |> add "seed" (Option.map Int64.to_string seed)
  in
  let* body = perform t (endpoint t "/v1/properties" query) in
  decode Parse.properties body

let take n list =
  let rec loop n acc = function
    | _ when n <= 0 -> List.rev acc
    | [] -> List.rev acc
    | x :: xs -> loop (n - 1) (x :: acc) xs
  in
  loop n [] list

let all_properties t ?(limit = 50) ?(locale = En) ?city ?country ?zone
    ?operator_slug ?product ?min_capacity ?min_price ?max_price ?currency ?sort
    ?seed () =
  if limit < 1 || limit > 200 then
    raise (Error (invalid "limit must be between 1 and 200"));
  let rec loop page seed_for_page collected remaining first =
    if remaining <= 0 then Lwt.return (collected, first)
    else
      let page_size = min 50 remaining in
      let* page_result =
        properties t ~locale ?city ?country ?zone ?operator_slug ?product
          ?min_capacity ?min_price ?max_price ?currency ?sort ~page ~page_size
          ?seed:seed_for_page ()
      in
      let got = take remaining page_result.properties in
      let collected = collected @ got in
      let remaining = remaining - List.length got in
      let first =
        match first with None -> Some page_result | Some _ as keep -> keep
      in
      let seed_for_page =
        match page_result.seed with Some s -> Some s | None -> seed_for_page
      in
      if got = [] || remaining <= 0 || page >= page_result.pagination.page_count
      then Lwt.return (collected, first)
      else loop (page + 1) seed_for_page collected remaining first
  in
  let* collected, first = loop 1 seed [] limit None in
  match first with
  | None -> Lwt.fail (Error (bad_response "empty catalogue walk"))
  | Some page -> Lwt.return { page with properties = collected }
