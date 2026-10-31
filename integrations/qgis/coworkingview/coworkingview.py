# -*- coding: utf-8 -*-
"""QGIS plugin entry: a toolbar button and a dock for CoworkingView workspaces."""

import os

from qgis.PyQt.QtCore import Qt
from qgis.PyQt.QtGui import QIcon
from qgis.PyQt.QtWidgets import QAction

from .dock import CoworkingViewDock


class CoworkingViewPlugin:
    """Loads CoworkingView workspaces as a point layer."""

    def __init__(self, iface):
        self.iface = iface
        self.action = None
        self.dock = None

    def initGui(self):
        icon_path = os.path.join(os.path.dirname(__file__), "icon.png")
        icon = QIcon(icon_path) if os.path.exists(icon_path) else QIcon()
        self.action = QAction(icon, "Show workspaces", self.iface.mainWindow())
        self.action.setObjectName("coworkingviewAction")
        self.action.setStatusTip("Load CoworkingView workspaces as points")
        self.action.setWhatsThis(
            "Load flexible workspaces from CoworkingView and open a listing."
        )
        self.action.triggered.connect(self._open)
        self.iface.addPluginToVectorMenu("CoworkingView", self.action)
        self.iface.addToolBarIcon(self.action)
        self.dock = CoworkingViewDock(self.iface)
        self.iface.addDockWidget(Qt.RightDockWidgetArea, self.dock)
        self.dock.hide()

    def unload(self):
        if self.dock is not None:
            self.dock.shutdown()
            self.iface.removeDockWidget(self.dock)
            self.dock.deleteLater()
            self.dock = None
        if self.action is not None:
            self.iface.removePluginVectorMenu("CoworkingView", self.action)
            self.iface.removeToolBarIcon(self.action)
            self.action.deleteLater()
            self.action = None

    def _open(self):
        if self.dock is None:
            return
        if self.dock.isVisible():
            self.dock.hide()
            return
        self.dock.show_and_load_cities()
