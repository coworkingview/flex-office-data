(* CoworkingView: Wolfram Function Repository submission for FlexOfficePriceIndex, without the
   definition notebook toolbar.

   Evaluate in a Wolfram Cloud notebook:
     Get["https://raw.githubusercontent.com/coworkingview/flex-office-data/<commit>/wolfram/submit-v7.wl"]

   By default this only checks: it loads the function from a pinned commit, runs live calls and the
   verification tests, builds the ResourceObject (Related Links = "ExternalLinks"), optionally deploys a
   private preview page, and returns an Association. Nothing is submitted.

   To submit, evaluate first (same session):  cwvDoSubmit = True;
   Optional: cwvPreview = False (skip the private preview deploy), cwvPublisherID = "..." (use that
   publisher ID), cwvForceResubmit = True (ignore the marker left by an earlier submission). *)
Module[{
   srcURL, markerName, doSubmit, doPreview, forceResubmit, pubOverride,
   try, roVariant, loaded, live, handle, rfIn, usage, notes, exSpecs, exCell, exNb, tests, testRes,
   links, meta, ro, roOK, rfCheck, preview, diag, forbidden, nameHits, checks, critical, pass,
   pid, marker, submit, linkInfo, strings},

  srcURL = "https://raw.githubusercontent.com/coworkingview/flex-office-data/714dc56732637fb2548fe2721661a8d4966d1062/wolfram/FlexOfficePriceIndex.wl";
  markerName = "cwv-wfr-FlexOfficePriceIndex-submission.m";
  doSubmit = TrueQ[Global`cwvDoSubmit];
  doPreview = ! MatchQ[Global`cwvPreview, False];
  forceResubmit = TrueQ[Global`cwvForceResubmit];
  pubOverride = If[StringQ[Global`cwvPublisherID] && Global`cwvPublisherID =!= "", Global`cwvPublisherID, None];

  SetAttributes[try, HoldAll];
  try[e_, t_ : 120] := Quiet[TimeConstrained[e, t, Failure["Timeout", <|"MessageTemplate" -> "Timed out"|>]]];

  (* 1. Function definitions from the pinned commit (URLBuild version of cwvFetch). *)
  loaded = try[Get[srcURL]; True, 60];
  live = <|
    "BerlinDatasetQ" -> try[Head[FlexOfficePriceIndex["Berlin"]] === Dataset],
    "BerlinPrivateOffice" -> try[FlexOfficePriceIndex["Berlin", "PrivateOffice"]],
    "AtlantisIsFailure" -> try[FailureQ[FlexOfficePriceIndex["Atlantis"]]]|>;
  live["BerlinPrivateOfficeInEuros"] = TrueQ[try[CompatibleUnitQ[live["BerlinPrivateOffice"], Quantity[1, "Euros"]]]];
  live["BerlinPrivateOffice"] = ToString[live["BerlinPrivateOffice"], InputForm];

  (* 2. Documentation, in the shape of scraped Function resources ("Documentation" -> Usage/Notes). *)
  handle = StyleBox[RowBox[{StyleBox["ResourceFunction", "ResourceFunctionSymbol"], "[",
      StyleBox["\"FlexOfficePriceIndex\"", "ResourceFunctionName"], "]"}], "ResourceFunctionHandle"];
  usage = {
    <|"Usage" -> BoxData[RowBox[{handle, "[", StyleBox["city", "TI"], "]"}]],
      "Description" -> TextData[{"gives a ", Cell[BoxData["Dataset"], "InlineFormula"],
        " of monthly price statistics (median, 25th and 75th percentiles, minimum, maximum and sample size) for flex desks, fixed desks and private offices in the city named ",
        Cell[BoxData[StyleBox["city", "TI"]], "InlineFormula"], "."}]|>,
    <|"Usage" -> BoxData[RowBox[{handle, "[", RowBox[{StyleBox["city", "TI"], ",", StyleBox["product", "TI"]}], "]"}]],
      "Description" -> TextData[{"gives the median monthly price of ", Cell[BoxData[StyleBox["product", "TI"]], "InlineFormula"],
        " in ", Cell[BoxData[StyleBox["city", "TI"]], "InlineFormula"], " as a ", Cell[BoxData["Quantity"], "InlineFormula"], " in euros."}]|>,
    <|"Usage" -> BoxData[RowBox[{handle, "[", StyleBox["entity", "TI"], "]"}]],
      "Description" -> TextData[{"uses the common name of the city ", Cell[BoxData[StyleBox["entity", "TI"]], "InlineFormula"],
        " (an ", Cell[BoxData["Entity"], "InlineFormula"], " of type \"City\")."}]|>};
  notes = {
    Cell[TextData[{"Data comes from the /v1/market/rates endpoint of the public CoworkingView REST API (",
      ButtonBox["API documentation", BaseStyle -> "Hyperlink", ButtonData -> {URL["https://coworkingview.com/en/api"], None}],
      "). No API key is needed. An Internet connection is required."}], "Notes"],
    Cell["Supported products are \"FlexDesk\" (hot desk), \"FixedDesk\" (dedicated desk) and \"PrivateOffice\" (price per workstation in a private office). Matching ignores case, spaces, hyphens and underscores.", "Notes"],
    Cell["Prices are monthly amounts in EUR, returned as Quantity objects. Figures are aggregated from published list prices of spaces in the CoworkingView catalogue and may change daily.", "Notes"],
    Cell["City names are normalized to lowercase slugs: diacritics are removed, German umlauts are transliterated and spaces become hyphens. Common local or English variants such as \"M\[UDoubleDot]nchen\", \"K\[ODoubleDot]ln\", \"Wien\", \"Lisbon\" and \"Seville\" are mapped to the index slug.", "Notes"],
    Cell["The \"InsufficientData\" column is True when the data provider flags the sample as too small to be representative.", "Notes"],
    Cell["A Failure object is returned for unknown cities, unknown products, invalid arguments, network errors or non-200 HTTP responses.", "Notes"],
    Cell[TextData[{"Data \[Copyright] CoworkingView, licensed under ",
      ButtonBox["CC BY 4.0", BaseStyle -> "Hyperlink", ButtonData -> {URL["https://creativecommons.org/licenses/by/4.0/"], None}],
      " (attribution: \"Source: CoworkingView Price Index\")."}], "Notes"]};

  (* 3. Example notebook: inputs shown as ResourceFunction["FlexOfficePriceIndex"][...], outputs from live calls. *)
  rfIn[code_String] := Module[{b},
    b = Block[{$Context = "CWVTMP`", $ContextPath = {"CWVTMP`", "System`"}, h},
      h = ToExpression[code, InputForm, Hold];
      If[h === $Failed, $Failed,
        h = h /. {Entity -> CWVTMP`Entity, Quantity -> CWVTMP`Quantity};
        Function[e, MakeBoxes[e, StandardForm], HoldAllComplete] @@ h]];
    If[b === $Failed, code,
      b /. {"FlexOfficePriceIndex" -> RowBox[{"ResourceFunction", "[", "\"FlexOfficePriceIndex\"", "]"}],
        s_String /; StringContainsQ[s, "`"] && ! StringStartsQ[s, "\""] :> StringReplace[s, RegularExpression["^.*`"] -> ""]}]];
  exSpecs = {
    {"Basic Examples", {
      {"Get monthly price statistics for flexible workspace in Berlin:", "FlexOfficePriceIndex[\"Berlin\"]"},
      {"Get the median monthly price of a private office workstation in Berlin:", "FlexOfficePriceIndex[\"Berlin\", \"PrivateOffice\"]"}}},
    {"Scope", {
      {"Local-language city names are accepted:", "FlexOfficePriceIndex[\"M\[UDoubleDot]nchen\", \"FlexDesk\"]"},
      {"Use a city Entity:", "FlexOfficePriceIndex[Entity[\"City\", {\"Hamburg\", \"Hamburg\", \"Germany\"}], \"FixedDesk\"]"}}},
    {"Applications", {
      {"Compare median private office prices across cities:", "AssociationMap[FlexOfficePriceIndex[#, \"PrivateOffice\"] &, {\"Berlin\", \"Munich\", \"Hamburg\", \"Madrid\", \"Barcelona\"}]"},
      {"Show the comparison as a bar chart:", "BarChart[QuantityMagnitude /@ AssociationMap[FlexOfficePriceIndex[#, \"PrivateOffice\"] &, {\"Berlin\", \"Munich\", \"Hamburg\", \"Madrid\", \"Barcelona\"}], ChartLabels -> Automatic]"}}},
    {"Properties and Relations", {
      {"List the available products:", "FlexOfficePriceIndex[\"Berlin\", \"Properties\"]"}}},
    {"Possible Issues", {
      {"Cities outside the index return a Failure:", "FlexOfficePriceIndex[\"Atlantis\"]"},
      {"Unknown product names also return a Failure:", "FlexOfficePriceIndex[\"Berlin\", \"Hotel\"]"}}},
    {"Neat Examples", {
      {"Find the monthly price gap between a private office workstation and a flex desk in Barcelona:", "FlexOfficePriceIndex[\"Barcelona\", \"PrivateOffice\"] - FlexOfficePriceIndex[\"Barcelona\", \"FlexDesk\"]"}}}};
  exCell[{text_String, code_String}] := Module[{in = rfIn[code], out},
    out = try[ToBoxes[ToExpression[code], StandardForm], 90];
    Join[{Cell[text, "Text"], Cell[BoxData[in], "Input"]},
      If[FailureQ[out] || out === $Failed, {}, {Cell[BoxData[out], "Output"]}]]];
  exNb = Notebook[Map[
     Function[sec, Cell[CellGroupData[Join[{Cell[sec[[1]], "Subsection"]},
        Flatten[Riffle[exCell /@ sec[[2]],
          Cell[BoxData[InterpretationBox[Cell["\t", "ExampleDelimiter"], $Line = 0; Null]], "ExampleDelimiter"]], 1]], Open]]],
     exSpecs]];

  tests = HoldComplete[
    VerificationTest[Head[FlexOfficePriceIndex["Atlantis"]], Failure, TestID -> "UnknownCityFailure"],
    VerificationTest[FlexOfficePriceIndex["Berlin", "Hotel"]["Tag"], "InvalidProduct", TestID -> "UnknownProductFailure"],
    VerificationTest[CompatibleUnitQ[FlexOfficePriceIndex["Berlin", "PrivateOffice"], Quantity[1, "Euros"]], True, TestID -> "BerlinPrivateOfficeInEuros"]];
  testRes = try[AssociationMap[Function[t, t["Outcome"]], List @@ tests] // KeyMap[#["TestID"] &], 120];

  (* 4. Metadata. "ExternalLinks" is what the published page shows as "Related Links" (h2 id="External-Links");
     "ContributorInformation" -> "ContributedBy" is the "Contributed by" line. *)
  links = {
    Hyperlink["CoworkingView Price Index", "https://coworkingview.com/en/tools/price-index"],
    Hyperlink["CoworkingView API documentation", "https://coworkingview.com/en/api"]};
  meta = <|
    "ResourceType" -> "Function",
    "Name" -> "FlexOfficePriceIndex",
    "Function" -> FlexOfficePriceIndex,
    "Description" -> "Retrieve monthly flexible-workspace prices for a European city from the CoworkingView Price Index",
    "Documentation" -> <|"Usage" -> usage, "Notes" -> notes|>,
    "ExampleNotebook" -> exNb,
    "VerificationTests" -> tests,
    "ContributorInformation" -> <|"ContributedBy" -> "CoworkingView"|>,
    "ExternalLinks" -> links,
    "Keywords" -> {"coworking", "office prices", "flexible workspace", "hot desk", "private office", "real estate", "rent", "Europe", "price index", "REST API"},
    "Categories" -> {"External Interfaces & Connections", "Financial Data & Computation", "Geographic Data & Computation"},
    "RelatedSymbols" -> {"URLRead", "URLBuild", "ImportByteArray", "Dataset", "Quantity", "Failure", "Entity", "CommonName"},
    "SourceMetadata" -> <|"Creator" -> "CoworkingView", "Publisher" -> "CoworkingView", "Title" -> "CoworkingView Price Index",
      "Source" -> URL["https://coworkingview.com/en/tools/price-index"], "Rights" -> "CC BY 4.0"|>,
    "WolframLanguageVersionRequired" -> "13.0+",
    "SubmissionNotes" -> "Wraps a free, keyless public REST API (OpenAPI spec: https://coworkingview.com/openapi.json). The contributor, CoworkingView, is the data provider. The function and its documentation were prepared with AI assistance. Example outputs reflect live data on the evaluation date and will drift over time."|>;
  ro = try[ResourceObject[meta], 120];
  roVariant = "Full";
  If[Head[ro] =!= ResourceObject,
    (* Fallback: leave out the keys most likely to be rejected; Related Links and Contributed by stay. *)
    ro = try[ResourceObject[KeyDrop[meta, {"Documentation", "SubmissionNotes", "RelatedSymbols", "WolframLanguageVersionRequired"}]], 120];
    roVariant = "Reduced (no Documentation/SubmissionNotes/RelatedSymbols/WolframLanguageVersionRequired)"];
  roOK = Head[ro] === ResourceObject;
  If[! roOK, roVariant = "None: " <> ToString[Short[ro, 10], InputForm]];
  rfCheck = If[roOK, try[CompatibleUnitQ[ResourceFunction[ro]["Berlin", "PrivateOffice"], Quantity[1, "Euros"]], 90], False];
  linkInfo = If[roOK, try[ToString[ro["ExternalLinks"], InputForm]], "NoResourceObject"];

  (* 5. Style / identity checks. *)
  strings = Cases[{meta["Description"], meta["SubmissionNotes"], meta["ContributorInformation"], notes, usage, links, exSpecs}, _String, Infinity];
  (* Optional: set cwvForbiddenNames = {"..."} in the session to also scan for other names; none are stored in this file. *)
  forbidden = Join[
    If[MatchQ[Global`cwvForbiddenNames, {__String}], ToLowerCase /@ Global`cwvForbiddenNames, {}],
    If[StringQ[$CloudAccountName], {ToLowerCase[$CloudAccountName]}, {}]];
  nameHits = Join[
    If[forbidden === {}, {}, Select[strings, StringContainsQ[ToLowerCase[#], forbidden] &]],
    Select[strings, StringContainsQ[#, RegularExpression["[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\\.[A-Za-z]{2,}"]] &],
    Select[Values[meta["ContributorInformation"]], # =!= "CoworkingView" &]];
  checks = <|
    "DefinitionLoaded" -> TrueQ[loaded],
    "LiveBerlinDataset" -> TrueQ[live["BerlinDatasetQ"]],
    "LivePrivateOfficeEuros" -> TrueQ[live["BerlinPrivateOfficeInEuros"]],
    "VerificationTestsPass" -> (AssociationQ[testRes] && Length[testRes] === 3 && AllTrue[Values[testRes], # === "Success" &]),
    "ResourceObjectBuilt" -> roOK,
    "ResourceFunctionWorks" -> TrueQ[rfCheck],
    "ExternalLinksAllCoworkingView" -> AllTrue[links, StringStartsQ[#[[2]], "https://coworkingview.com/"] &],
    "ContributedByCoworkingViewOnly" -> (meta["ContributorInformation"] === <|"ContributedBy" -> "CoworkingView"|>),
    "NoPersonalNames" -> (nameHits === {}),
    "DescriptionNoTrailingPeriod" -> ! StringEndsQ[meta["Description"], "."],
    "ExamplesWithOutput" -> Count[exNb, Cell[_, "Output", ___], Infinity],
    "ExamplesInputs" -> Count[exNb, Cell[_, "Input", ___], Infinity]|>;
  critical = {"DefinitionLoaded", "LiveBerlinDataset", "LivePrivateOfficeEuros", "VerificationTestsPass", "ResourceObjectBuilt",
    "ResourceFunctionWorks", "ExternalLinksAllCoworkingView", "ContributedByCoworkingViewOnly", "NoPersonalNames"};
  pass = AllTrue[critical, TrueQ[checks[#]] &];

  (* 6. Environment diagnostics (never the Wolfram ID itself). *)
  pid = If[StringQ[pubOverride], pubOverride, Quiet[$PublisherID]];
  diag = <|
    "CloudConnected" -> TrueQ[$CloudConnected],
    "CloudAccountName" -> Quiet[$CloudAccountName],
    "PublisherID" -> pid,
    "Version" -> $VersionNumber,
    "Paclets" -> try[AssociationMap[Function[p, Replace[PacletFind[p], {{po_, ___} :> po["Version"], _ -> Missing["NotFound"]}]],
        {"DefinitionNotebookClient", "FunctionResource", "ResourceSystemClient"}], 30],
    "CurrentTemplateVersion" -> try[Needs["DefinitionNotebookClient`"];
        FirstCase[DefinitionNotebookClient`DefinitionTemplate["Function"], ("TemplateVersion" -> v_String) :> v, Missing["NotFound"], Infinity], 60]|>;

  (* 7. Private preview of the repository page (shows Related Links as rendered). *)
  preview = If[doPreview && roOK,
    try[Replace[CloudDeploy[ro, "FlexOfficePriceIndex-v7-preview", Permissions -> "Private"], co_CloudObject :> First[co]], 180],
    "Skipped"];

  (* 8. Submission, only with cwvDoSubmit = True, all critical checks passed and no earlier submission marker. *)
  marker = Quiet[CloudGet[CloudObject[markerName]]];
  submit = Which[
    ! doSubmit, "NotRequested (set cwvDoSubmit = True and evaluate again)",
    ! pass, Failure["ChecksFailed", <|"Failed" -> Select[critical, ! TrueQ[checks[#]] &]|>],
    AssociationQ[marker] && ! forceResubmit, Failure["AlreadySubmitted", <|"Marker" -> marker|>],
    True, Module[{r, rs, sid},
      r = try[If[StringQ[pid], ResourceSubmit[ro, PublisherID -> pid], ResourceSubmit[ro]], 300];
      rs = ToString[Short[r, 30], InputForm];
      sid = Quiet[Replace[r, {s_Success :> Lookup[s[[2]], "SubmissionID", Lookup[s[[2]], "ID", Missing["NotInResult"]]], _ -> Missing["NoSuccess"]}]];
      If[Head[r] === Success,
        Quiet[CloudPut[<|"Date" -> DateString["ISODateTime"], "SubmissionID" -> sid, "Result" -> rs|>, CloudObject[markerName], Permissions -> "Private"]]];
      <|"Head" -> Head[r], "SubmissionID" -> sid, "Result" -> rs|>]];

  <|"Mode" -> If[doSubmit, "Submit", "CheckOnly"],
    "AllCriticalChecksPass" -> pass,
    "Checks" -> checks,
    "Live" -> live,
    "VerificationTests" -> testRes,
    "NameHits" -> nameHits,
    "Metadata" -> <|"Name" -> meta["Name"], "Description" -> meta["Description"],
      "ContributedBy" -> meta[["ContributorInformation", "ContributedBy"]], "ExternalLinks" -> linkInfo,
      "Categories" -> meta["Categories"], "Keywords" -> meta["Keywords"],
      "ResourceObjectVariant" -> roVariant,
      "ResourceObjectProperties" -> If[roOK, try[Sort[ro["Properties"]], 30], Missing["NoResourceObject"]]|>,
    "Environment" -> diag,
    "PreviewURL" -> preview,
    "EarlierSubmissionMarker" -> If[AssociationQ[marker], marker, None],
    "Submission" -> submit|>
]
