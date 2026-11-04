FlexOfficePriceIndex // ClearAll;

FlexOfficePriceIndex::nocity = "No published price data for city `1` (slug \"`2`\").";
FlexOfficePriceIndex::badprod = "Unknown product `1`. Use one of `2`.";
FlexOfficePriceIndex::http = "The CoworkingView API returned HTTP status `1`.";

$cwvProducts = <|"FlexDesk" -> "flex_desk", "FixedDesk" -> "fix_desk", "PrivateOffice" -> "private_office"|>;

$cwvAliases = <|"muenchen" -> "munich", "koeln" -> "cologne", "wien" -> "vienna",
   "lisbon" -> "lisboa", "seville" -> "sevilla", "nuernberg" -> "nuremberg",
   "hannover" -> "hanover", "duesseldorf" -> "dusseldorf", "lubeck" -> "luebeck",
   "milano" -> "milan", "roma" -> "rome", "firenze" -> "florence", "napoli" -> "naples",
   "torino" -> "turin", "zuerich" -> "zurich", "zurich" -> "zurich", "frankfurt-am-main" -> "frankfurt"|>;

cwvSlug[s_String] := Module[{t},
   t = ToLowerCase[StringTrim[s]];
   t = StringReplace[t, {"\[ADoubleDot]" -> "ae", "\[ODoubleDot]" -> "oe", "\[UDoubleDot]" -> "ue", "\[SZ]" -> "ss"}];
   t = RemoveDiacritics[t];
   t = StringReplace[t, {"'" -> "", "." -> ""}];
   t = StringTrim[StringReplace[t, Except[LetterCharacter | DigitCharacter] .. -> "-"], "-"];
   Lookup[$cwvAliases, t, t]
  ];
cwvSlug[e_Entity] := Module[{n = Quiet[CommonName[e]]},
   If[StringQ[n], cwvSlug[n], Failure["InvalidCity", <|"MessageTemplate" -> "Cannot get a name for `1`.", "MessageParameters" -> {e}|>]]
  ];
cwvSlug[_] := $Failed;

cwvEUR[a_Association] := If[NumericQ[a["amount"]], Quantity[a["amount"], "Euros"], Missing["NotAvailable"]];
cwvEUR[_] := Missing["NotAvailable"];

cwvFetch[slug_String] := Module[{resp, status, json},
   resp = URLRead[HTTPRequest["https://api.coworkingview.com/v1/market/rates",
      <|"Query" -> {"city" -> slug, "locale" -> "en", "currency" -> "EUR"}|>], TimeConstraint -> 30];
   If[FailureQ[resp], Return[resp]];
   status = resp["StatusCode"];
   If[status =!= 200,
    Return[Failure["HTTPError", <|"MessageTemplate" :> FlexOfficePriceIndex::http, "MessageParameters" -> {status}, "StatusCode" -> status|>]]];
   json = Quiet[ImportByteArray[resp["BodyByteArray"], "RawJSON"]];
   If[!AssociationQ[json], Return[Failure["BadResponse", <|"MessageTemplate" -> "Could not parse the API response."|>]]];
   json
  ];

cwvCity[input_] := Module[{slug, json, cities},
   slug = cwvSlug[input];
   If[FailureQ[slug], Return[slug]];
   If[!StringQ[slug] || slug === "",
    Return[Failure["InvalidCity", <|"MessageTemplate" -> "`1` is not a valid city name.", "MessageParameters" -> {input}|>]]];
   json = cwvFetch[slug];
   If[FailureQ[json], Return[json]];
   cities = Select[Lookup[Lookup[json, "data", <||>], "cities", {}], AssociationQ];
   If[cities === {},
    Return[Failure["NoData", <|"MessageTemplate" :> FlexOfficePriceIndex::nocity, "MessageParameters" -> {input, slug}|>]]];
   First[cities]
  ];

cwvRows[c_Association] := Module[{byType, figs, row},
   byType = AssociationMap[Function[t, SelectFirst[Lookup[c, "byType", {}], #["optionType"] === t &, <||>]], Values[$cwvProducts]];
   figs = AssociationMap[Function[t, SelectFirst[Lookup[c, "figures", {}], #["optionType"] === t &, <||>]], Values[$cwvProducts]];
   row[t_] := <|
     "Median" -> cwvEUR[Lookup[figs[t], "median", Lookup[byType[t], "median", None]]],
     "P25" -> cwvEUR[Lookup[figs[t], "p25", None]],
     "P75" -> cwvEUR[Lookup[figs[t], "p75", None]],
     "Min" -> cwvEUR[Lookup[byType[t], "min", None]],
     "Max" -> cwvEUR[Lookup[byType[t], "max", None]],
     "SampleSize" -> Lookup[figs[t], "sampleSize", Lookup[byType[t], "sampleSize", Missing["NotAvailable"]]],
     "InsufficientData" -> Lookup[figs[t], "insufficientData", Missing["NotAvailable"]]|>;
   AssociationThread[Keys[$cwvProducts], row /@ Values[$cwvProducts]]
  ];

FlexOfficePriceIndex[city : (_String | _Entity)] := Module[{c = cwvCity[city]},
   If[FailureQ[c], c, Dataset[cwvRows[c]]]
  ];

FlexOfficePriceIndex[city : (_String | _Entity), product_String] := Module[{key, c},
   key = SelectFirst[Keys[$cwvProducts],
     ToLowerCase[StringDelete[#, " " | "_" | "-"]] === ToLowerCase[StringDelete[product, " " | "_" | "-"]] &, Missing[]];
   If[MissingQ[key],
    Return[Failure["InvalidProduct", <|"MessageTemplate" :> FlexOfficePriceIndex::badprod, "MessageParameters" -> {product, Keys[$cwvProducts]}|>]]];
   c = cwvCity[city];
   If[FailureQ[c], c, cwvRows[c][key]["Median"]]
  ];

FlexOfficePriceIndex[city : (_String | _Entity), "Properties"] := Keys[$cwvProducts];

FlexOfficePriceIndex[args___] := Failure["InvalidArguments",
   <|"MessageTemplate" -> "FlexOfficePriceIndex expects a city name or Entity, optionally followed by a product name.", "Arguments" -> {args}|>];
