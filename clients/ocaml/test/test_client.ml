let contains needle haystack =
  let n = String.length needle in
  let h = String.length haystack in
  let rec loop i =
    if i + n > h then false
    else if String.sub haystack i n = needle then true
    else loop (i + 1)
  in
  loop 0

let fixture name =
  let path = Filename.concat "fixtures" name in
  In_channel.with_open_text path In_channel.input_all

let http ?(status = 200) ?(headers = []) body =
  { Coworkingview.status; headers; body }

let fake handler =
  let calls = ref [] in
  let sleeps = ref [] in
  let transport =
    {
      Coworkingview.get =
        (fun ~headers url ->
          calls := (url, headers) :: !calls;
          handler ~headers url);
    }
  in
  let sleep seconds =
    sleeps := seconds :: !sleeps;
    Lwt.return_unit
  in
  (calls, sleeps, Coworkingview.make ~transport ~sleep ())

let urls calls = List.rev_map fst !calls

let param url name =
  match Uri.get_query_param (Uri.of_string url) name with
  | Some value -> value
  | None -> Alcotest.failf "missing query parameter %s in %s" name url

let absent url name =
  match Uri.get_query_param (Uri.of_string url) name with
  | None -> ()
  | Some value -> Alcotest.failf "unexpected %s=%s" name value

let header headers name =
  let want = String.lowercase_ascii name in
  let rec loop = function
    | [] -> Alcotest.failf "missing header %s" name
    | (key, value) :: rest ->
        if String.lowercase_ascii key = want then value else loop rest
  in
  loop headers

let run fn = Lwt_main.run (fn ())

let error fn =
  try
    ignore (run fn);
    Alcotest.fail "expected Coworkingview.Error"
  with Coworkingview.Error e -> e

let find_city rates slug =
  match
    List.find_opt
      (fun (city : Coworkingview.city_rates) -> city.city.slug = slug)
      rates
  with
  | Some city -> city
  | None -> Alcotest.failf "city %s not in fixture" slug

let find_figure figures option_type =
  match
    List.find_opt
      (fun (figure : Coworkingview.figure) -> figure.option_type = option_type)
      figures
  with
  | Some figure -> figure
  | None -> Alcotest.failf "figure %s missing" option_type

let find_property properties slug =
  match
    List.find_opt
      (fun (property : Coworkingview.property) -> property.slug = slug)
      properties
  with
  | Some property -> property
  | None -> Alcotest.failf "property %s missing" slug

let money actual expected =
  Alcotest.(check (float 1e-6)) "amount" expected actual

let money_amount (value : Coworkingview.money option) =
  Option.map (fun (price : Coworkingview.money) -> price.amount) value

let test_rates_fixture () =
  let body = fixture "market_rates.json" in
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let rates =
    run (fun () -> Coworkingview.market_rates client ~city:"berlin" ())
  in
  Alcotest.(check string) "license" "CC-BY-4.0" rates.license;
  Alcotest.(check string)
    "license url" "https://creativecommons.org/licenses/by/4.0/"
    rates.license_url;
  Alcotest.(check bool)
    "attribution" true
    (contains "CC BY 4.0" rates.attribution);
  Alcotest.(check int) "total properties" 209 rates.total_properties;
  Alcotest.(check int) "total price points" 475 rates.total_price_points;
  Alcotest.(check string) "as of" "2026-10-27T21:06:48.313Z" rates.as_of;
  Alcotest.(check (option string))
    "contract" (Some "1.0.0") rates.contract_version;
  let berlin = find_city rates.cities "berlin" in
  Alcotest.(check string) "name" "Berlin" berlin.city.name;
  Alcotest.(check string) "country" "DE" berlin.country_code;
  Alcotest.(check string) "currency" "EUR" berlin.currency;
  Alcotest.(check int) "properties" 85 berlin.property_count;
  Alcotest.(check int) "operators" 48 berlin.operator_count;
  Alcotest.(check int) "sample" 85 berlin.sample_size;
  money berlin.entry_median.amount 265.;
  let flex = find_figure berlin.figures "flex_desk" in
  money flex.median.amount 214.;
  money flex.p25.amount 199.;
  money flex.p75.amount 292.;
  Alcotest.(check int) "flex n" 72 flex.sample_size;
  Alcotest.(check int) "flex spaces" 66 flex.property_count;
  (match berlin.day_pass with
  | None -> Alcotest.fail "berlin day pass"
  | Some day -> money day.median.amount 35.);
  (match berlin.meeting_room with
  | None -> Alcotest.fail "berlin meeting room"
  | Some room -> money room.median.amount 32.);
  Alcotest.(check bool) "buildings" true (berlin.buildings <> []);
  match rates.unpublished with
  | [ city ] ->
      Alcotest.(check string) "unpublished" "example-town" city.city.slug;
      Alcotest.(check (option bool)) "flag" (Some true) city.insufficient_data
  | cities ->
      Alcotest.failf "expected 1 unpublished city, got %d" (List.length cities)

let test_rates_usd () =
  let body = fixture "market_rates_berlin_usd.json" in
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let rates =
    run (fun () ->
        Coworkingview.market_rates client ~city:"berlin" ~currency:Usd ())
  in
  let berlin = find_city rates.cities "berlin" in
  Alcotest.(check string) "usd" "USD" berlin.currency;
  money (find_figure berlin.figures "flex_desk").median.amount 233.

let test_rates_query () =
  let body = fixture "market_rates.json" in
  let calls, _sleeps, client =
    fake (fun ~headers _ ->
        Alcotest.(check string)
          "accept" "application/json" (header headers "accept");
        Alcotest.(check string)
          "user agent" Coworkingview.version
          (let ua = header headers "user-agent" in
           if contains ("coworkingview-ocaml/" ^ Coworkingview.version) ua then
             Coworkingview.version
           else ua);
        Lwt.return (http body))
  in
  let _ =
    run (fun () ->
        Coworkingview.market_rates client ~locale:De ~city:"berlin"
          ~country:"germany" ~currency:Usd ())
  in
  match urls calls with
  | [ url ] ->
      Alcotest.(check string) "locale" "de" (param url "locale");
      Alcotest.(check string) "city" "berlin" (param url "city");
      Alcotest.(check string) "country" "germany" (param url "country");
      Alcotest.(check string) "currency" "USD" (param url "currency");
      Alcotest.(check bool)
        "path" true
        (String.starts_with
           ~prefix:"https://api.coworkingview.com/v1/market/rates" url)
  | got -> Alcotest.failf "expected 1 call, got %d" (List.length got)

let test_properties_fixture () =
  let body = fixture "properties_berlin.json" in
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let page =
    run (fun () -> Coworkingview.properties client ~city:"berlin" ())
  in
  Alcotest.(check int) "rows" 3 (List.length page.properties);
  Alcotest.(check int) "page" 1 page.pagination.page;
  Alcotest.(check int) "page size" 3 page.pagination.page_size;
  Alcotest.(check int) "total" 110 page.pagination.total;
  Alcotest.(check int) "page count" 37 page.pagination.page_count;
  Alcotest.(check (option int64)) "seed" (Some 2085917097L) page.seed;
  (match page.catalogue_notice with
  | Some notice ->
      Alcotest.(check bool)
        "notice" true
        (contains "Systematic extraction" notice)
  | None -> Alcotest.fail "catalogue notice");
  (match page.citation with
  | Some citation ->
      Alcotest.(check string) "source" "CoworkingView" citation.source
  | None -> Alcotest.fail "citation");
  let first =
    find_property page.properties "sankt-oberholz-rosenthaler-berlin"
  in
  Alcotest.(check string) "city" "berlin" first.city.slug;
  (match first.zone with
  | Some zone -> Alcotest.(check string) "zone" "mitte" zone.slug
  | None -> Alcotest.fail "zone");
  Alcotest.(check string) "operator" "St. Oberholz" first.operator_name;
  money first.lat 52.5294539;
  Alcotest.(check bool) "featured" true first.featured;
  Alcotest.(check bool) "wifi" true (List.mem "wifi" first.amenities);
  Alcotest.(check (option (float 1e-6)))
    "no from price" None
    (money_amount first.from_price);
  (match first.market with
  | Some market ->
      Alcotest.(check string) "verdict" "around" market.verdict;
      money market.median.amount 214.
  | None -> Alcotest.fail "market");
  let second = find_property page.properties "smartspaces-berlin-spandau" in
  Alcotest.(check (option int)) "capacity" (Some 30) second.capacity;
  (match second.from_price with
  | Some price ->
      money price.amount 750.;
      Alcotest.(check string) "cur" "EUR" price.currency
  | None -> Alcotest.fail "from price");
  Alcotest.(check (option string))
    "billing" (Some "month") second.from_billing_period;
  let third = find_property page.properties "regus-charlottenburg-berlin" in
  Alcotest.(check bool) "no market" true (third.market = None)

let test_properties_empty () =
  let body = fixture "properties_empty.json" in
  let calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let page =
    run (fun () -> Coworkingview.all_properties client ~city:"nowhere-xyz" ())
  in
  Alcotest.(check int) "rows" 0 (List.length page.properties);
  Alcotest.(check int) "total" 0 page.pagination.total;
  Alcotest.(check int) "pages" 0 page.pagination.page_count;
  Alcotest.(check int) "calls" 1 (List.length (urls calls))

let test_properties_query () =
  let body = fixture "properties_empty.json" in
  let calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let _ =
    run (fun () ->
        Coworkingview.properties client ~locale:Es ~city:"madrid" ~zone:"centro"
          ~operator_slug:"regus" ~product:Meeting_room ~min_capacity:4
          ~min_price:10.5 ~max_price:40. ~currency:Eur ~sort:Price_asc ~page:2
          ~page_size:20 ~seed:99L ())
  in
  match urls calls with
  | [ url ] ->
      Alcotest.(check string) "locale" "es" (param url "locale");
      Alcotest.(check string) "city" "madrid" (param url "city");
      Alcotest.(check string) "zone" "centro" (param url "zone");
      Alcotest.(check string) "operator" "regus" (param url "operator");
      Alcotest.(check string)
        "product" "meeting_room"
        (param url "pricingOptionType");
      Alcotest.(check string) "cap" "4" (param url "minCapacity");
      Alcotest.(check string) "min" "10.5" (param url "minPrice");
      Alcotest.(check string) "max" "40" (param url "maxPrice");
      Alcotest.(check string) "cur" "EUR" (param url "currency");
      Alcotest.(check string) "sort" "price-asc" (param url "sortBy");
      Alcotest.(check string) "page" "2" (param url "page");
      Alcotest.(check string) "page size" "20" (param url "pageSize");
      Alcotest.(check string) "seed" "99" (param url "seed");
      absent url "country"
  | got -> Alcotest.failf "expected 1 call, got %d" (List.length got)

let test_default_query_omits_filters () =
  let body = fixture "properties_empty.json" in
  let calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let _ = run (fun () -> Coworkingview.properties client ()) in
  match urls calls with
  | [ url ] ->
      Alcotest.(check string) "locale" "en" (param url "locale");
      Alcotest.(check string) "page" "1" (param url "page");
      Alcotest.(check string) "page size" "50" (param url "pageSize");
      List.iter (absent url)
        [
          "city";
          "country";
          "zone";
          "operator";
          "pricingOptionType";
          "sortBy";
          "seed";
          "currency";
        ]
  | got -> Alcotest.failf "expected 1 call, got %d" (List.length got)

let listing (property : Coworkingview.property) =
  `Assoc
    [
      ("slug", `String property.slug);
      ("title", `String property.title);
      ("countryCode", `String property.country_code);
      ( "city",
        `Assoc
          [
            ("slug", `String property.city.slug);
            ("name", `String property.city.name);
          ] );
      ( "operator",
        `Assoc
          [
            ("slug", `String property.operator_slug);
            ("name", `String property.operator_name);
          ] );
      ( "coordinates",
        `Assoc [ ("lat", `Float property.lat); ("lng", `Float property.lng) ] );
      ("featured", `Bool property.featured);
      ("updatedAt", `String property.updated_at);
      ( "amenities",
        `List (List.map (fun amenity -> `String amenity) property.amenities) );
    ]

let page_body ~page ~page_count ~page_size ~total ~seed items =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("data", `List (List.map listing items));
         ( "meta",
           `Assoc
             [
               ("contractVersion", `String "1.0.0");
               ( "pagination",
                 `Assoc
                   [
                     ("page", `Int page);
                     ("pageSize", `Int page_size);
                     ("total", `Int total);
                     ("pageCount", `Int page_count);
                   ] );
               ("seed", `Intlit (Int64.to_string seed));
               ( "catalogueNotice",
                 `String "Systematic extraction is not permitted." );
             ] );
       ])

let test_pagination_forwards_seed_and_stops () =
  let body = fixture "properties_berlin.json" in
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let first =
    run (fun () ->
        Coworkingview.properties client ~city:"berlin" ~page_size:3 ())
  in
  let page1 = [ List.nth first.properties 0; List.nth first.properties 1 ] in
  let page2 = [ List.nth first.properties 2 ] in
  let calls, _sleeps, client =
    fake (fun ~headers:_ url ->
        let page = int_of_string (param url "page") in
        let body =
          if page = 1 then
            page_body ~page:1 ~page_count:2 ~page_size:2 ~total:3
              ~seed:2085917097L page1
          else
            page_body ~page:2 ~page_count:2 ~page_size:1 ~total:3
              ~seed:2085917097L page2
        in
        Lwt.return (http body))
  in
  let collected =
    run (fun () ->
        Coworkingview.all_properties client ~city:"berlin" ~limit:10 ())
  in
  Alcotest.(check int) "rows" 3 (List.length collected.properties);
  Alcotest.(check string)
    "third" "regus-charlottenburg-berlin" (List.nth collected.properties 2).slug;
  (match urls calls with
  | [ first_url; second_url ] ->
      Alcotest.(check string) "page size" "10" (param first_url "pageSize");
      absent first_url "seed";
      Alcotest.(check string) "forwarded" "2085917097" (param second_url "seed")
  | got -> Alcotest.failf "expected 2 calls, got %d" (List.length got));
  Alcotest.(check int) "total stays" 3 collected.pagination.total

let test_limit_trims_without_a_second_page () =
  let body = fixture "properties_berlin.json" in
  let calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http body))
  in
  let page =
    run (fun () ->
        Coworkingview.all_properties client ~city:"berlin" ~limit:2 ())
  in
  Alcotest.(check int) "trimmed" 2 (List.length page.properties);
  Alcotest.(check int) "one call" 1 (List.length (urls calls));
  Alcotest.(check string) "asked" "2" (param (List.hd (urls calls)) "pageSize")

let test_validation_error () =
  let body = fixture "error_validation.json" in
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http ~status:400 body))
  in
  let err =
    error (fun () -> Coworkingview.market_rates client ~currency:Ves ())
  in
  Alcotest.(check int) "status" 400 err.status;
  Alcotest.(check string) "code" "VALIDATION_FAILED" err.code;
  Alcotest.(check (option string)) "title" (Some "Validation failed") err.title;
  (match err.detail with
  | Some detail -> Alcotest.(check bool) "ves" true (contains "VES" detail)
  | None -> Alcotest.fail "detail");
  match err.errors with
  | [ field ] -> Alcotest.(check string) "path" "currency" field.path
  | fields ->
      Alcotest.failf "expected 1 field error, got %d" (List.length fields)

let test_retry () =
  let ok_body = fixture "properties_empty.json" in
  let calls, sleeps, client =
    let n = ref 0 in
    fake (fun ~headers:_ _ ->
        incr n;
        if !n = 1 then
          Lwt.return
            (http ~status:503 ~headers:[ ("Retry-After", "100") ] "unavailable")
        else Lwt.return (http ok_body))
  in
  let page =
    run (fun () -> Coworkingview.properties client ~city:"berlin" ())
  in
  Alcotest.(check int) "rows" 0 (List.length page.properties);
  Alcotest.(check int) "attempts" 2 (List.length (urls calls));
  Alcotest.(check (list (float 1e-6))) "capped delay" [ 10. ] (List.rev !sleeps)

let test_retry_delay () =
  let ok_body = fixture "properties_empty.json" in
  let once headers expected =
    let n = ref 0 in
    let _calls, sleeps, client =
      fake (fun ~headers:_ _ ->
          incr n;
          if !n = 1 then Lwt.return (http ~status:500 ~headers "down")
          else Lwt.return (http ok_body))
    in
    let _ = run (fun () -> Coworkingview.properties client ()) in
    Alcotest.(check (list (float 1e-6))) "delay" [ expected ] (List.rev !sleeps)
  in
  once [ ("RateLimit-Reset", "4") ] 4.;
  once [] 2.

let test_no_second_retry () =
  let calls, sleeps, client =
    fake (fun ~headers:_ _ ->
        Lwt.return (http ~status:500 ~headers:[ ("Retry-After", "1") ] "down"))
  in
  let err = error (fun () -> Coworkingview.properties client ()) in
  Alcotest.(check int) "status" 500 err.status;
  Alcotest.(check string) "code" "HTTP_500" err.code;
  Alcotest.(check int) "attempts" 2 (List.length (urls calls));
  Alcotest.(check int) "slept once" 1 (List.length !sleeps)

let test_bad_json () =
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.return (http "not-json"))
  in
  let err = error (fun () -> Coworkingview.market_rates client ()) in
  Alcotest.(check int) "status" 200 err.status;
  Alcotest.(check string) "code" "BAD_RESPONSE" err.code

let test_missing_data () =
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ ->
        Lwt.return (http {|{"meta":{"contractVersion":"1.0.0"}}|}))
  in
  let err = error (fun () -> Coworkingview.market_rates client ()) in
  Alcotest.(check string) "code" "BAD_RESPONSE" err.code

let test_connection_failure () =
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.fail (Failure "connection refused"))
  in
  let err =
    error (fun () -> Coworkingview.properties client ~city:"berlin" ())
  in
  Alcotest.(check string) "code" "CONNECTION" err.code;
  Alcotest.(check int) "status" 0 err.status

let detail_has err needle =
  match err.Coworkingview.detail with
  | Some message ->
      if not (contains needle message) then
        Alcotest.failf "detail %S does not contain %S" message needle
  | None -> Alcotest.fail "missing detail"

let test_invalid_arguments () =
  let _calls, _sleeps, client =
    fake (fun ~headers:_ _ -> Lwt.fail (Failure "should not be called"))
  in
  let check needle fn =
    let err = error fn in
    Alcotest.(check string) "code" "INVALID_ARGUMENT" err.code;
    detail_has err needle
  in
  check "page" (fun () -> Coworkingview.properties client ~page:0 ());
  check "page_size" (fun () -> Coworkingview.properties client ~page_size:51 ());
  check "city" (fun () -> Coworkingview.properties client ~city:"  " ());
  check "limit" (fun () -> Coworkingview.all_properties client ~limit:201 ());
  check "limit" (fun () -> Coworkingview.all_properties client ~limit:0 ());
  Alcotest.check_raises "timeout"
    (Invalid_argument "Coworkingview.make: timeout must be positive") (fun () ->
      ignore (Coworkingview.make ~timeout:0. ()))

let test_base_url_and_env () =
  let body = fixture "properties_empty.json" in
  let calls, _sleeps, client =
    let calls = ref [] in
    let transport =
      {
        Coworkingview.get =
          (fun ~headers:_ url ->
            calls := url :: !calls;
            Lwt.return (http body));
      }
    in
    ( calls,
      ref [],
      Coworkingview.make ~base_url:"https://example.test/" ~transport
        ~sleep:(fun _ -> Lwt.return_unit)
        () )
  in
  let _ = run (fun () -> Coworkingview.properties client ()) in
  (match List.rev !calls with
  | [ url ] ->
      Alcotest.(check bool)
        "stripped" true
        (String.starts_with ~prefix:"https://example.test/v1/properties" url)
  | _ -> Alcotest.fail "one call");
  Unix.putenv "COWORKINGVIEW_API_URL" "http://from-env.test";
  let rates_body = fixture "market_rates.json" in
  let calls = ref [] in
  let client =
    let transport =
      {
        Coworkingview.get =
          (fun ~headers:_ url ->
            calls := url :: !calls;
            Lwt.return (http rates_body));
      }
    in
    Coworkingview.make ~transport ~sleep:(fun _ -> Lwt.return_unit) ()
  in
  let _ = run (fun () -> Coworkingview.market_rates client ()) in
  (match List.rev !calls with
  | [ url ] ->
      Alcotest.(check bool)
        "env" true
        (String.starts_with ~prefix:"http://from-env.test/v1/market/rates" url)
  | _ -> Alcotest.fail "env call");
  Unix.putenv "COWORKINGVIEW_API_URL" ""

let () =
  let open Alcotest in
  run "coworkingview"
    [
      ( "rates",
        [
          test_case "fixture" `Quick test_rates_fixture;
          test_case "usd fixture" `Quick test_rates_usd;
          test_case "query" `Quick test_rates_query;
        ] );
      ( "properties",
        [
          test_case "fixture" `Quick test_properties_fixture;
          test_case "empty" `Quick test_properties_empty;
          test_case "query" `Quick test_properties_query;
          test_case "defaults" `Quick test_default_query_omits_filters;
          test_case "pages" `Quick test_pagination_forwards_seed_and_stops;
          test_case "limit" `Quick test_limit_trims_without_a_second_page;
        ] );
      ( "http",
        [
          test_case "validation" `Quick test_validation_error;
          test_case "retry cap" `Quick test_retry;
          test_case "retry delay" `Quick test_retry_delay;
          test_case "one retry" `Quick test_no_second_retry;
          test_case "bad json" `Quick test_bad_json;
          test_case "missing data" `Quick test_missing_data;
          test_case "connection" `Quick test_connection_failure;
          test_case "arguments" `Quick test_invalid_arguments;
          test_case "base url" `Quick test_base_url_and_env;
        ] );
    ]
