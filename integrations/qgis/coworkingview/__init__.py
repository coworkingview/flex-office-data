# -*- coding: utf-8 -*-
"""CoworkingView QGIS plugin.

Copyright (C) 2026 CoworkingView

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.
"""


def classFactory(iface):  # pylint: disable=invalid-name
    """QGIS calls this to construct the plugin."""
    from .coworkingview import CoworkingViewPlugin

    return CoworkingViewPlugin(iface)
