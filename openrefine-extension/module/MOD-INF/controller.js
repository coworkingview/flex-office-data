/*
 * CoworkingView Price Index extension for OpenRefine.
 * https://coworkingview.com
 */

function init() {
  Packages.com.google.refine.grel.ControlFunctionRegistry.registerFunction(
    "coworkingviewPriceIndex",
    new Packages.com.coworkingview.openrefine.PriceIndexFunction()
  );
}
