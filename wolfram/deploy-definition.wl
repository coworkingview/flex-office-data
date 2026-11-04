(* Rebuilds the code/input cells of the CoworkingView Function Repository definition
   notebook with the running kernel's own MakeBoxes and deploys it to the caller's cloud. *)
Module[{url, nb, reparse, nb2, codes, bad, obj, orig, ctxLeft},
  url = "https://raw.githubusercontent.com/coworkingview/flex-office-data/main/wolfram/FlexOfficePriceIndex-definition.nb";
  nb = ToExpression[Import[url, "Text"]];
  reparse[b_] := Module[{s = b //. RowBox[l : {___String}] :> StringJoin[l], r},
    If[! StringQ[s], b,
      r = Quiet[Block[{$Context = "CWVTMP`", $ContextPath = {"CWVTMP`", "System`"}, h},
        h = ToExpression[s, InputForm, Hold];
        If[h === $Failed, $Failed,
          h = h /. {HTTPRequest -> CWVTMP`HTTPRequest, HTTPResponse -> CWVTMP`HTTPResponse, URL -> CWVTMP`URL,
             Failure -> CWVTMP`Failure, Quantity -> CWVTMP`Quantity, Entity -> CWVTMP`Entity, Dataset -> CWVTMP`Dataset,
             Missing -> CWVTMP`Missing, VerificationTest -> CWVTMP`VerificationTest, TestObject -> CWVTMP`TestObject,
             Hyperlink -> CWVTMP`Hyperlink, ByteArray -> CWVTMP`ByteArray, ResourceFunction -> CWVTMP`ResourceFunction};
          Function[e, MakeBoxes[e, StandardForm], HoldAllComplete] @@ h]]];
      If[r === $Failed, b,
        r /. str_String /; ! StringStartsQ[str, "\""] :> StringReplace[str, RegularExpression["(CWVTMP|\\$CellContext|Notebook\\$\\$[0-9$]*|Global)`"] -> ""]]]];
  nb2 = nb /. Cell[BoxData[b_], sty : ("Code" | "Input"), o___] :> Cell[BoxData[reparse[b]], sty, o];
  ctxLeft = Count[Cases[nb2, Cell[BoxData[b_], "Code" | "Input", ___] :> b, Infinity], str_String /; StringContainsQ[str, "`"] && ! StringStartsQ[str, "\""], Infinity];
  codes = Cases[nb2, Cell[BoxData[b_], "Code", ___] :> b, Infinity];
  bad = Select[codes, Quiet[ToExpression[#, StandardForm, Hold]] === $Failed &];
  orig = Select[Cases[nb, Cell[BoxData[b_], "Code", ___] :> b, Infinity], Quiet[ToExpression[#, StandardForm, Hold]] === $Failed &];
  obj = CloudDeploy[nb2, "FlexOfficePriceIndex-definition-v5.nb", Permissions -> "Private"];
  <|"CodeCells" -> Length[codes], "UnparsableCodeCells" -> Length[bad], "OriginalUnparsable" -> Length[orig], "SameAsOriginal" -> Count[MapThread[SameQ, {codes, Cases[nb, Cell[BoxData[b_], "Code", ___] :> b, Infinity]}], True], "ContextPrefixesLeft" -> ctxLeft, "Sample" -> Take[Union[Cases[Cases[nb2, Cell[BoxData[b_], "Code", ___] :> b, Infinity], str_String /; StringContainsQ[str, "`"] && ! StringStartsQ[str, "\""], Infinity]], UpTo[5]], "FetchCell" -> FirstCase[codes, b_ /; ! FreeQ[b, "cwvFetch"] && ! FreeQ[b, "URLRead"], None], "Deployed" -> obj|>
]
