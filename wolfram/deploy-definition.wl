(* Rebuilds the code/input cells of the CoworkingView Function Repository definition
   notebook with the running kernel's own MakeBoxes and deploys it to the caller's cloud. *)
Module[{url, nb, reparse, nb2, codes, bad, obj, orig},
  url = "https://raw.githubusercontent.com/coworkingview/flex-office-data/main/wolfram/FlexOfficePriceIndex-definition.nb";
  nb = ToExpression[Import[url, "Text"]];
  reparse[b_] := Module[{s = b //. RowBox[l_List] :> StringJoin[l], r},
    If[! StringQ[s], b,
      r = Quiet[ToExpression[s, InputForm, Function[e, MakeBoxes[e, StandardForm], HoldAllComplete]]];
      If[r === $Failed, b, r]]];
  nb2 = nb /. Cell[BoxData[b_], sty : ("Code" | "Input"), o___] :> Cell[BoxData[reparse[b]], sty, o];
  codes = Cases[nb2, Cell[BoxData[b_], "Code", ___] :> b, Infinity];
  bad = Select[codes, Quiet[ToExpression[#, StandardForm, Hold]] === $Failed &];
  orig = Select[Cases[nb, Cell[BoxData[b_], "Code", ___] :> b, Infinity], Quiet[ToExpression[#, StandardForm, Hold]] === $Failed &];
  obj = CloudDeploy[nb2, "FlexOfficePriceIndex-definition-v5.nb", Permissions -> "Private"];
  <|"CodeCells" -> Length[codes], "UnparsableCodeCells" -> Length[bad], "OriginalUnparsable" -> Length[orig], "Deployed" -> obj|>
]
