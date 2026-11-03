"""Matplotlib bar charts of the CoworkingView Price Index.

``plot_city_rates`` and ``plot_rate_comparison`` call
``GET https://api.coworkingview.com/v1/market/rates`` and draw medians.
The Price Index is CC BY 4.0. Every chart sets the x-axis label to
``Data: CoworkingView Price Index (CC BY 4.0)``.

>>> import matplotlib.pyplot as plt
>>> import mpl_coworkingview as cv
>>> fig, ax = plt.subplots()
>>> cv.plot_city_rates(ax, "berlin")  # doctest: +SKIP

No network call is made at import time.
"""

from __future__ import annotations

from ._http import Client
from ._version import __version__
from .exceptions import APIError, CoworkingViewError
from .plot import ATTRIBUTION, plot_city_rates, plot_rate_comparison

__all__ = [
    "ATTRIBUTION",
    "APIError",
    "Client",
    "CoworkingViewError",
    "__version__",
    "plot_city_rates",
    "plot_rate_comparison",
]
