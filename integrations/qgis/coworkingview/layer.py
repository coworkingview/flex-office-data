# -*- coding: utf-8 -*-
"""Turn a workspace search into a memory point layer.

QGIS imports stay in this module so ``client.py`` can be tested without QGIS.
"""

from qgis.core import (
    Qgis,
    QgsAction,
    QgsCoordinateReferenceSystem,
    QgsCoordinateTransform,
    QgsCsException,
    QgsFeature,
    QgsGeometry,
    QgsMarkerSymbol,
    QgsMessageLog,
    QgsPointXY,
    QgsRectangle,
    QgsSingleSymbolRenderer,
    QgsVectorLayer,
)

from .client import layer_abstract

LAYER_PROPERTY = "coworkingview_layer"
LAYER_ROLE = "spaces"
LOG_NAME = "CoworkingView"


def layer_name(result):
    """Legend title for a search."""
    title = "CoworkingView - {0}".format(result.city_name)
    if result.type_label:
        title = "{0} - {1}".format(title, result.type_label)
    return title


def make_layer(result):
    """Build an in-memory point layer. Fields are name, city, address, type, url."""
    uri = (
        "Point?crs=EPSG:4326"
        "&field=name:string(255)"
        "&field=city:string(120)"
        "&field=address:string(255)"
        "&field=type:string(255)"
        "&field=url:string(300)"
    )
    layer = QgsVectorLayer(uri, layer_name(result), "memory")
    if not layer.isValid():
        raise RuntimeError("QGIS could not create the CoworkingView layer.")
    features = [_feature(layer, space) for space in result.workspaces]
    if features:
        added = layer.dataProvider().addFeatures(features)
        if not _added(added):
            raise RuntimeError("QGIS could not add the CoworkingView workspaces to the layer.")
    layer.updateExtents()
    layer.setCrs(QgsCoordinateReferenceSystem("EPSG:4326"))
    layer.setReadOnly(True)
    layer.setDisplayExpression('"name"')
    layer.setMapTipTemplate(
        '<b>[% "name" %]</b><br>[% "city" %]<br>[% "address" %]<br>[% "type" %]'
    )
    layer.setCustomProperty(LAYER_PROPERTY, LAYER_ROLE)
    _set_abstract(layer, layer_abstract(result))
    _style(layer)
    _add_open_action(layer)
    return layer


def zoom_extent(layer, project):
    """Layer extent in the project CRS, padded so a single point is visible."""
    if layer.featureCount() == 0:
        return None
    extent = QgsRectangle(layer.extent())
    if extent.isNull():
        return None
    if extent.width() == 0 or extent.height() == 0:
        extent.grow(0.01)
    else:
        extent.scale(1.2)
    destination = project.crs()
    if not layer.crs().isValid() or not destination.isValid() or layer.crs() == destination:
        return extent
    transform = QgsCoordinateTransform(layer.crs(), destination, project)
    try:
        return transform.transformBoundingBox(extent)
    except QgsCsException as err:
        QgsMessageLog.logMessage(
            "Could not reproject the CoworkingView extent: {0}".format(err),
            LOG_NAME,
            Qgis.Warning,
        )
        return None


def previous_layer_ids(project):
    """Ids of layers this plugin added earlier."""
    found = []
    for layer in project.mapLayers().values():
        if layer.customProperty(LAYER_PROPERTY) == LAYER_ROLE:
            found.append(layer.id())
    return found


def remove_previous_layers(project, keep_id):
    """Drop earlier CoworkingView searches so a new filter replaces the last one."""
    for layer_id in previous_layer_ids(project):
        if layer_id != keep_id:
            project.removeMapLayer(layer_id)


def _feature(layer, space):
    feature = QgsFeature(layer.fields())
    feature.setAttributes(
        [space.name, space.city, space.address, space.workspace_type, space.url]
    )
    feature.setGeometry(QgsGeometry.fromPointXY(QgsPointXY(space.lng, space.lat)))
    return feature


def _added(added):
    if isinstance(added, tuple):
        return bool(added[0])
    return bool(added)


def _style(layer):
    symbol = QgsMarkerSymbol.createSimple(
        {
            "name": "circle",
            "color": "#1c1c1c",
            "outline_color": "#c4a35a",
            "outline_width": "0.4",
            "size": "3",
        }
    )
    if symbol is not None:
        layer.setRenderer(QgsSingleSymbolRenderer(symbol))


def _add_open_action(layer):
    action = QgsAction(
        QgsAction.OpenUrl,
        "Open on CoworkingView",
        '[% "url" %]',
        False,
    )
    scopes = ["Feature", "Canvas", "Field"]
    try:
        action.setActionScopes(scopes)
    except TypeError:
        action.setActionScopes(set(scopes))
    layer.actions().addAction(action)


def _set_abstract(layer, text):
    metadata = layer.metadata()
    metadata.setAbstract(text)
    layer.setMetadata(metadata)
