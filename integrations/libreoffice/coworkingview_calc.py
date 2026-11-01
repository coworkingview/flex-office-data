# CoworkingView Calc add-in. LibreOffice loads this file as a Python component.
# The helper module lives in pythonpath/ and is imported by name.

import math
import os
import sys

import unohelper
from com.coworkingview.calc import XCoworkingView
from com.sun.star.lang import Locale, XLocalizable, XServiceInfo, XServiceName
from com.sun.star.sheet import XAddIn

_HERE = os.path.dirname(os.path.abspath(__file__))
_PYTHONPATH = os.path.join(_HERE, "pythonpath")
if _PYTHONPATH not in sys.path:
    sys.path.insert(0, _PYTHONPATH)

import coworkingview_api as api

IMPLEMENTATION = "com.coworkingview.calc.CoworkingViewImpl"
SERVICE = "com.coworkingview.calc.CoworkingView"

_HELP = {name: spec for name, spec in api.FUNCTIONS}


def _text(value):
    """Turn a Calc argument into text. Blank and empty numerics stay blank."""
    if value is None:
        return ""
    type_name = type(value).__name__
    if type_name in ("Void", "Null"):
        return ""
    if isinstance(value, float) and math.isnan(value):
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def _cell(fn, *args):
    try:
        return fn(*args)
    except api.CwvError as exc:
        return "CWV: " + str(exc)
    except Exception:  # noqa: BLE001 - a formula must return text, not raise into Calc
        return "CWV: unexpected error"


class CoworkingViewAddIn(
    unohelper.Base,
    XCoworkingView,
    XAddIn,
    XLocalizable,
    XServiceName,
    XServiceInfo,
):
    """Spreadsheet functions. The network runs only when a formula asks for data."""

    def __init__(self, ctx):
        self.ctx = ctx
        self._locale = Locale()
        self._locale.Language = "en"
        self._locale.Country = "US"
        self._locale.Variant = ""
        self._client = None

    def _api(self):
        if self._client is None:
            self._client = api.Client()
        return self._client

    def CWV_SPACES(self, City):
        return _cell(api.spaces, self._api(), _text(City))

    def CWV_PRICE(self, City, Product):
        return _cell(api.price, self._api(), _text(City), _text(Product))

    def CWV_RATE(self, City, Product, Stat):
        return _cell(api.rate, self._api(), _text(City), _text(Product), _text(Stat))

    def CWV_CURRENCY(self, City):
        return _cell(api.currency, self._api(), _text(City))

    def CWV_SAMPLE(self, City, Product):
        return _cell(api.sample, self._api(), _text(City), _text(Product))

    def CWV_ASOF(self, City):
        return _cell(api.index_as_of, self._api(), _text(City))

    def CWV_SOURCE(self):
        return api.source()

    def CWV_ATTRIBUTION(self, City):
        return _cell(api.index_attribution, self._api(), _text(City))

    def getProgrammaticFuntionName(self, aDisplayName):
        # The UNO method name is spelled Funtion. That is the published API.
        key = (aDisplayName or "").upper()
        if key in _HELP:
            return key
        return aDisplayName or ""

    def getDisplayFunctionName(self, aProgrammaticName):
        key = (aProgrammaticName or "").upper()
        if key in _HELP:
            return key
        return aProgrammaticName or ""

    def getFunctionDescription(self, aProgrammaticName):
        spec = _HELP.get((aProgrammaticName or "").upper())
        if spec is None:
            return ""
        return spec["description"]

    def getDisplayArgumentName(self, aProgrammaticFunctionName, nArgument):
        spec = _HELP.get((aProgrammaticFunctionName or "").upper())
        if spec is None or nArgument < 0 or nArgument >= len(spec["params"]):
            return ""
        return spec["params"][nArgument][0]

    def getArgumentDescription(self, aProgrammaticFunctionName, nArgument):
        spec = _HELP.get((aProgrammaticFunctionName or "").upper())
        if spec is None or nArgument < 0 or nArgument >= len(spec["params"]):
            return ""
        return spec["params"][nArgument][1]

    def getProgrammaticCategoryName(self, aProgrammaticFunctionName):
        if (aProgrammaticFunctionName or "").upper() in _HELP:
            return "Add-In"
        return ""

    def getDisplayCategoryName(self, aProgrammaticFunctionName):
        return self.getProgrammaticCategoryName(aProgrammaticFunctionName)

    def setLocale(self, locale):
        self._locale = locale

    def getLocale(self):
        return self._locale

    def getServiceName(self):
        return SERVICE

    def getImplementationName(self):
        return IMPLEMENTATION

    def supportsService(self, name):
        return name == SERVICE

    def getSupportedServiceNames(self):
        return (SERVICE,)


g_ImplementationHelper = unohelper.ImplementationHelper()
g_ImplementationHelper.addImplementation(
    CoworkingViewAddIn,
    IMPLEMENTATION,
    (SERVICE,),
)
