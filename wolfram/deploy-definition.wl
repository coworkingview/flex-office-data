(* Rebuilds the code/input cells of the CoworkingView Function Repository definition
   notebook with the running kernel's own MakeBoxes, deploys it to the caller's cloud as
   FlexOfficePriceIndex-definition-v6.nb and checks the notebook read back from that cloud object. *)
Module[{url, nb, reparse, nb2, codeOf, check, origBad, obj, dep, depRead, res},
  (* Pinned to the commit whose definition notebook uses URLBuild, so no cached raw copy is read. *)
  url = "https://raw.githubusercontent.com/coworkingview/flex-office-data/ddd4c173d0806f788cf7902b4dfc5664ee7bd2f5/wolfram/FlexOfficePriceIndex-definition.nb";
  nb = ToExpression[Import[url, "Text"]];
  reparse[b_] := Module[{s = b //. RowBox[l : {___String}] :> StringJoin[l], r},
    If[! StringQ[s], b,
      (* Safety net only: the pinned notebook no longer contains HTTPRequest. *)
      s = StringReplace[s, RegularExpression["HTTPRequest\\[\\s*(\"https://api\\.coworkingview\\.com/v1/market/rates\"),\\s*<\\|\\s*\"Query\"\\s*->\\s*(\\{[^}]*\\})\\s*\\|>\\s*\\]"] -> "URLBuild[$1, $2]"];
      r = Quiet[Block[{$Context = "CWVTMP`", $ContextPath = {"CWVTMP`", "System`"}, h},
        h = ToExpression[s, InputForm, Hold];
        If[h === $Failed, $Failed,
          (* Inert stand-ins, so MakeBoxes never draws summary or icon boxes. *)
          h = h /. {HTTPRequest -> CWVTMP`HTTPRequest, HTTPResponse -> CWVTMP`HTTPResponse, URL -> CWVTMP`URL,
             URLRead -> CWVTMP`URLRead, URLBuild -> CWVTMP`URLBuild,
             Failure -> CWVTMP`Failure, Quantity -> CWVTMP`Quantity, Entity -> CWVTMP`Entity, Dataset -> CWVTMP`Dataset,
             Missing -> CWVTMP`Missing, VerificationTest -> CWVTMP`VerificationTest, TestObject -> CWVTMP`TestObject,
             Hyperlink -> CWVTMP`Hyperlink, ByteArray -> CWVTMP`ByteArray, ResourceFunction -> CWVTMP`ResourceFunction};
          Function[e, MakeBoxes[e, StandardForm], HoldAllComplete] @@ h]]];
      If[r === $Failed, b,
        r /. str_String /; ! StringStartsQ[str, "\""] :> StringReplace[str, RegularExpression["(CWVTMP|\\$CellContext|Notebook\\$\\$[0-9$]*|Global)`"] -> ""]]]];
  nb2 = nb /. Cell[BoxData[b_], sty : ("Code" | "Input"), o___] :> Cell[BoxData[reparse[b]], sty, o];
  codeOf[n_] := Cases[n, Cell[BoxData[b_], "Code", ___] :> b, Infinity];
  (* String checks on ToString[boxes, InputForm] of each code cell. *)
  check[n_] := Module[{cs = codeOf[n], strs, fetch, has},
    strs = ToString[#, InputForm] & /@ cs;
    fetch = Select[strs, StringContainsQ[#, "\"cwvFetch\""] && StringContainsQ[#, "URLRead"] &];
    has[t_] := AnyTrue[fetch, StringContainsQ[#, t] &];
    <|"CodeCells" -> Length[cs],
      "CwvFetchCells" -> Length[fetch],
      "CwvFetchHasURLBuild" -> (fetch =!= {} && AllTrue[fetch, StringContainsQ[#, "URLBuild"] &]),
      "CwvFetchHasHTTPRequest" -> has["HTTPRequest"],
      "CwvFetchTokens" -> AssociationMap[has, {"HTTPRequest", "Hyperlink", "$Failed", "$CellContext", "URLBuild"}],
      (* $Failed is legitimate only as its own token (cwvSlug[_] := $Failed). *)
      "AnyFailedOrHyperlinkInCode" -> Or @@ MapThread[
         Function[{str, c}, StringContainsQ[str, "Hyperlink" | "InterpretationBox" | "TemplateBox" | "$CellContext"] ||
           StringCount[str, "$Failed"] > Count[c, "$Failed", {0, Infinity}]], {strs, cs}],
      "ContextPrefixesLeft" -> Count[cs, str_String /; StringContainsQ[str, "`"] && ! StringStartsQ[str, "\""], Infinity],
      "UnparsableCodeCells" -> Count[cs, b_ /; Quiet[ToExpression[b, StandardForm, Hold]] === $Failed]|>];
  origBad = Count[codeOf[nb], b_ /; Quiet[ToExpression[b, StandardForm, Hold]] === $Failed];
  obj = CloudDeploy[nb2, "FlexOfficePriceIndex-definition-v6.nb", Permissions -> "Private"];
  (* Read the deployed object back instead of trusting the expression that was sent. *)
  dep = Quiet[Import[obj, "NB"]];
  If[Head[dep] =!= Notebook, dep = Quiet[CloudGet[obj]]];
  If[Head[dep] =!= Notebook, dep = Quiet[ToExpression[Import[obj, "Text"]]]];
  depRead = Head[dep] === Notebook;
  res = check[If[depRead, dep, nb2]];
  Join[res, <|
    "CheckedObject" -> If[depRead, "DeployedNotebook", "BuiltExpression (deployed notebook could not be read back)"],
    "DeployedSameAsBuilt" -> If[depRead, codeOf[dep] === codeOf[nb2], Missing["NotRead"]],
    "SourceHasHTTPRequest" -> ! FreeQ[codeOf[nb], s_String /; StringContainsQ[s, "HTTPRequest"]],
    "OriginalUnparsable" -> origBad,
    "Deployed" -> obj|>]
]
