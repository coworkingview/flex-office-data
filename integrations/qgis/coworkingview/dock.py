# -*- coding: utf-8 -*-
"""Dock widget: choose a city and a workspace type, then load the points."""

import os

from qgis.core import Qgis, QgsApplication, QgsMessageLog, QgsProject, QgsTask
from qgis.gui import QgsMapLayerAction, QgsMapLayerActionRegistry
from qgis.PyQt.QtCore import QObject, QUrl, Qt, pyqtSignal
from qgis.PyQt.QtGui import QDesktopServices, QIcon
from qgis.PyQt.QtWidgets import (
    QComboBox,
    QDockWidget,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .client import WORKSPACE_TYPES, Cancelled, Client, CoworkingViewError, status_message
from .layer import LOG_NAME, make_layer, remove_previous_layers, zoom_extent


def _cancelled(exception):
    """True for our cancel and for the message QGIS uses when a task is cancelled."""
    if isinstance(exception, Cancelled):
        return True
    return exception is not None and str(exception) == "Task canceled"


class _Progress(QObject):
    """Queues progress text from the task thread onto the dock."""

    progress = pyqtSignal(int, int, str)


class CoworkingViewDock(QDockWidget):
    """Small dock for the city and workspace-type filters."""

    def __init__(self, iface):
        super().__init__("CoworkingView", iface.mainWindow())
        self.iface = iface
        self._alive = True
        self._cities = {}
        self._layer = None
        self._map_action = None
        self._city_task = None
        self._space_task = None
        self._bridge = _Progress(self)
        self._bridge.progress.connect(self._on_progress)
        self.setObjectName("CoworkingViewDock")
        icon = os.path.join(os.path.dirname(__file__), "icon.png")
        if os.path.exists(icon):
            self.setWindowIcon(QIcon(icon))
        self._build()

    def shutdown(self):
        """Cancel background loads and detach signals. The layer stays on the map."""
        self._alive = False
        try:
            self._bridge.progress.disconnect(self._on_progress)
        except TypeError:
            pass
        self._cancel_tasks()
        self._detach_layer()

    def show_and_load_cities(self):
        """Show the dock and fill the city list the first time it is opened."""
        self.show()
        self.raise_()
        if not self._cities and self._city_task is None:
            self._start_cities()

    def _build(self):
        intro = QLabel(
            "Flexible workspaces from the CoworkingView catalogue. "
            "Choose a city and a workspace type, then load them as points."
        )
        intro.setWordWrap(True)
        self._city = QComboBox()
        self._city.addItem("Choose a city", None)
        self._type = QComboBox()
        self._type.addItem("All types", None)
        for code, label in WORKSPACE_TYPES:
            self._type.addItem(label, code)
        self._load = QPushButton("Load spaces")
        self._load.clicked.connect(self._on_load)
        self._open = QPushButton("Open on CoworkingView")
        self._open.setEnabled(False)
        self._open.setToolTip("Select one workspace on the map or in the attribute table.")
        self._open.clicked.connect(self._open_selected)
        self._progress = QProgressBar()
        self._progress.hide()
        self._status = QLabel("Open this panel to load the city list.")
        self._status.setWordWrap(True)
        self._status.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self._notice = QTextEdit()
        self._notice.setReadOnly(True)
        self._notice.setMaximumHeight(110)
        self._notice.hide()
        form = QFormLayout()
        form.addRow("City", self._city)
        form.addRow("Workspace type", self._type)
        buttons = QHBoxLayout()
        buttons.addWidget(self._load)
        buttons.addWidget(self._open)
        layout = QVBoxLayout()
        layout.addWidget(intro)
        layout.addLayout(form)
        layout.addLayout(buttons)
        layout.addWidget(self._progress)
        layout.addWidget(self._status)
        layout.addWidget(self._notice)
        layout.addStretch(1)
        holder = QWidget()
        holder.setLayout(layout)
        self.setWidget(holder)

    def _on_load(self):
        if self._space_task is not None:
            self._space_task.cancel()
            self._load.setEnabled(False)
            self._set_status("Cancelling.")
            return
        if self._city_task is not None:
            self._set_status("Still loading the city list.")
            return
        if not self._cities:
            self._start_cities()
            self._set_status("Loading the city list. Choose a city when it appears.")
            return
        city_slug = self._city.currentData()
        city = self._cities.get(city_slug)
        if city is None:
            self._set_status("Choose a city.")
            return
        self._start_spaces(city, self._type.currentData())

    def _start_cities(self):
        task = QgsTask.fromFunction(
            "CoworkingView cities",
            self._cities_work,
            on_finished=self._cities_finished,
        )
        self._city_task = task
        self._set_busy(True)
        self._set_status("Loading cities from CoworkingView.")
        QgsApplication.taskManager().addTask(task)

    def _cities_work(self, task):
        # A dict is always truthy. QGIS 3.22 drops the result argument when the
        # task returns a falsy value, which an empty city tuple is.
        return {"cities": Client().list_cities(should_cancel=task.isCanceled)}

    def _cities_finished(self, exception, result=None):
        self._city_task = None
        if not self._alive:
            return
        self._set_busy(False)
        if _cancelled(exception):
            self._set_status("City list cancelled.")
            return
        if exception is not None:
            self._fail(exception)
            return
        cities = result.get("cities") if isinstance(result, dict) else None
        if cities is None:
            self._set_status("Could not read the city list from CoworkingView.")
            return
        self._fill_cities(cities)
        if cities:
            self._set_status("Choose a city and a workspace type, then load spaces.")
        else:
            self._set_status("The CoworkingView API returned no cities with listed spaces.")

    def _fill_cities(self, cities):
        self._city.clear()
        self._cities = {}
        self._city.addItem("Choose a city", None)
        for city in cities:
            self._cities[city.slug] = city
            self._city.addItem(_city_label(city), city.slug)

    def _start_spaces(self, city, type_code):
        task = QgsTask.fromFunction(
            "CoworkingView: {0}".format(city.name),
            self._spaces_work,
            on_finished=self._spaces_finished,
            city_slug=city.slug,
            city_name=city.name,
            type_code=type_code,
        )
        self._space_task = task
        self._set_busy(True)
        self._progress.setRange(0, 0)
        self._progress.setValue(0)
        self._progress.show()
        QgsApplication.taskManager().addTask(task)

    def _spaces_work(self, task, city_slug, city_name, type_code):
        def on_progress(done, total, message):
            if not self._alive:
                return
            self._bridge.progress.emit(int(done), int(total), message)
            if total:
                task.setProgress(100.0 * done / total)

        return Client().load_spaces(
            city_slug,
            city_name,
            pricing_option_type=type_code,
            on_progress=on_progress,
            should_cancel=task.isCanceled,
        )

    def _spaces_finished(self, exception, result=None):
        self._space_task = None
        if not self._alive:
            return
        self._set_busy(False)
        self._progress.hide()
        if _cancelled(exception):
            self._set_status("Load cancelled.")
            return
        if exception is not None:
            self._fail(exception)
            return
        if result is None:
            self._fail(CoworkingViewError("CoworkingView did not return a workspace list."))
            return
        try:
            self._show_result(result)
        except Exception as err:
            self._fail(err)

    def _show_result(self, result):
        layer = make_layer(result)
        project = _project()
        self._detach_layer()
        remove_previous_layers(project, None)
        project.addMapLayer(layer)
        self._attach_layer(layer)
        extent = zoom_extent(layer, project)
        if extent is not None:
            self.iface.mapCanvas().setExtent(extent)
        self.iface.mapCanvas().refresh()
        self.iface.setActiveLayer(layer)
        self._set_status(status_message(result))
        notice = []
        if result.citation:
            notice.append(result.citation)
        if result.notice:
            notice.append(result.notice)
        if notice:
            self._notice.setPlainText("\n\n".join(notice))
            self._notice.show()
        else:
            self._notice.hide()

    def _on_progress(self, done, total, message):
        if not self._alive:
            return
        self._set_status(message)
        if total <= 0:
            self._progress.setRange(0, 0)
            return
        self._progress.setRange(0, total)
        self._progress.setValue(min(done, total))

    def _attach_layer(self, layer):
        self._detach_layer()
        self._layer = layer
        layer.selectionChanged.connect(self._on_selection)
        self._install_map_action(layer)
        self._update_open_button()

    def _detach_layer(self):
        layer = self._layer
        self._layer = None
        if layer is not None:
            try:
                layer.selectionChanged.disconnect(self._on_selection)
            except (TypeError, RuntimeError):
                pass
        self._remove_map_action()
        self._open.setEnabled(False)

    def _install_map_action(self, layer):
        try:
            action = QgsMapLayerAction(
                "Open on CoworkingView",
                self.iface.mainWindow(),
                layer,
                QgsMapLayerAction.SingleFeature,
            )
        except Exception as err:
            QgsMessageLog.logMessage(
                "Could not add the Open on CoworkingView map action: {0}".format(err),
                LOG_NAME,
                Qgis.Warning,
            )
            return
        action.triggeredForFeature.connect(self._open_feature)
        self._map_action = action
        QgsMapLayerActionRegistry.instance().addMapLayerAction(action)

    def _remove_map_action(self):
        action = self._map_action
        self._map_action = None
        if action is None:
            return
        try:
            QgsMapLayerActionRegistry.instance().removeMapLayerAction(action)
            action.deleteLater()
        except (RuntimeError, TypeError):
            pass

    def _on_selection(self, *_args):
        self._update_open_button()

    def _update_open_button(self):
        layer = self._layer
        enabled = False
        if layer is not None:
            try:
                enabled = layer.selectedFeatureCount() == 1
            except RuntimeError:
                enabled = False
        self._open.setEnabled(enabled)

    def _open_selected(self):
        layer = self._layer
        if layer is None:
            self._set_status("Load spaces, select one, then open it on CoworkingView.")
            return
        try:
            features = layer.selectedFeatures()
        except RuntimeError:
            self._set_status("The workspace layer is no longer available.")
            return
        if len(features) != 1:
            self._set_status("Select one workspace, then use Open on CoworkingView.")
            return
        self._open_feature(layer, features[0])

    def _open_feature(self, _layer, feature):
        url = feature.attribute("url")
        if not isinstance(url, str) or not url.startswith("https://"):
            self._set_status("This workspace has no CoworkingView listing URL.")
            return
        QDesktopServices.openUrl(QUrl(url))

    def _set_busy(self, busy):
        self._city.setEnabled(not busy)
        self._type.setEnabled(not busy)
        cancellable = busy and self._space_task is not None
        self._load.setText("Cancel" if cancellable else "Load spaces")
        self._load.setEnabled(True)

    def _cancel_tasks(self):
        for task in (self._city_task, self._space_task):
            if task is not None:
                task.cancel()

    def _fail(self, exception):
        if isinstance(exception, CoworkingViewError):
            message = str(exception)
        else:
            message = "Could not load CoworkingView workspaces. {0}".format(exception)
        self._set_status(message)
        QgsMessageLog.logMessage(message, LOG_NAME, Qgis.Warning)
        self.iface.messageBar().pushMessage("CoworkingView", message, Qgis.Warning, 8)

    def _set_status(self, text):
        self._status.setText(text)


def _city_label(city):
    label = city.name
    if city.country_code:
        label = "{0} ({1})".format(label, city.country_code)
    if city.property_count is not None:
        label = "{0} · {1}".format(label, city.property_count)
    return label


def _project():
    return QgsProject.instance()
