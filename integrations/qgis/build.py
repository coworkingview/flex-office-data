#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build coworkingview.zip for plugins.qgis.org.

The zip has a single top-level folder named coworkingview/. Run from anywhere:

    python3 integrations/qgis/build.py
"""

from __future__ import annotations

import argparse
import configparser
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PLUGIN_DIR = ROOT / "coworkingview"
DEFAULT_OUTPUT = ROOT / "dist" / "coworkingview.zip"
PACKAGE = "coworkingview"

REQUIRED_METADATA = (
    "name",
    "description",
    "version",
    "qgisMinimumVersion",
    "author",
    "email",
    "about",
    "tracker",
    "repository",
)
PACKAGE_FILES = (
    "__init__.py",
    "metadata.txt",
    "coworkingview.py",
    "client.py",
    "dock.py",
    "layer.py",
    "icon.png",
    "LICENSE",
    "README.md",
)
FORBIDDEN = ("__pycache__", ".git", "__MACOSX", ".pyc")


def build(output=DEFAULT_OUTPUT):
    """Write the plugin zip and return its path."""
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in PACKAGE_FILES:
            path = PLUGIN_DIR / name
            if not path.is_file():
                raise SystemExit("missing plugin file: {0}".format(path))
            archive.write(path, "{0}/{1}".format(PACKAGE, name))
    return output


def validate(path):
    """Return a list of problems. An empty list means the zip is acceptable."""
    path = Path(path)
    errors = []
    if not path.is_file():
        return ["zip does not exist: {0}".format(path)]
    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile as err:
        return ["not a zip file: {0}".format(err)]
    with archive:
        names = archive.namelist()
        if archive.testzip():
            errors.append("crc error in {0}".format(archive.testzip()))
        parents = {name.split("/")[0] for name in names if name}
        if parents != {PACKAGE}:
            found = ", ".join(sorted(parents))
            errors.append("top-level folder must be {0}, found {1}".format(PACKAGE, found))
        for name in names:
            if name.startswith("/") or ".." in name.split("/"):
                errors.append("unsafe path: {0}".format(name))
            parts = name.split("/")
            for forbidden in FORBIDDEN:
                if forbidden in parts or name.endswith(".pyc"):
                    errors.append("forbidden entry: {0}".format(name))
        for required in ("__init__.py", "metadata.txt", "LICENSE", "icon.png", "README.md"):
            member = "{0}/{1}".format(PACKAGE, required)
            if member not in names:
                errors.append("missing {0}".format(member))
        init_name = "{0}/__init__.py".format(PACKAGE)
        if init_name in names and b"def classFactory" not in archive.read(init_name):
            errors.append("__init__.py does not define classFactory")
        icon_name = "{0}/icon.png".format(PACKAGE)
        if icon_name in names and not archive.read(icon_name).startswith(b"\x89PNG\r\n\x1a\n"):
            errors.append("icon.png is not a PNG")
        meta_name = "{0}/metadata.txt".format(PACKAGE)
        if meta_name in names:
            errors.extend(_metadata_errors(archive.read(meta_name).decode("utf-8")))
        license_name = "{0}/LICENSE".format(PACKAGE)
        if license_name in names:
            license_text = archive.read(license_name).decode("utf-8")
            if "GNU GENERAL PUBLIC LICENSE" not in license_text:
                errors.append("LICENSE is not the GNU GPL")
            if "any later version" not in license_text:
                errors.append("LICENSE does not grant GPL-2.0-or-later")
    return errors


def _metadata_errors(text):
    parser = configparser.ConfigParser()
    parser.optionxform = str
    try:
        parser.read_string(text)
    except configparser.Error as err:
        return ["metadata.txt: {0}".format(err)]
    if not parser.has_section("general"):
        return ["metadata.txt has no [general] section"]
    general = dict(parser.items("general"))
    errors = []
    for key in REQUIRED_METADATA:
        if key not in general or not general[key].strip():
            errors.append("metadata.txt missing {0}".format(key))
    expected = {
        "name": "CoworkingView",
        "version": "0.1.0",
        "qgisMinimumVersion": "3.22",
        "author": "CoworkingView",
        "email": "info@coworkingview.com",
        "homepage": "https://coworkingview.com",
        "repository": "https://github.com/coworkingview/flex-office-data",
        "tracker": "https://github.com/coworkingview/flex-office-data/issues",
    }
    for key, value in expected.items():
        if general.get(key) != value:
            errors.append("metadata {0} must be {1}".format(key, value))
    homepage = general.get("homepage", "")
    if "www." in homepage:
        errors.append("homepage must not use www")
    version_py = (PLUGIN_DIR / "client.py").read_text(encoding="utf-8")
    if 'VERSION = "{0}"'.format(general.get("version", "")) not in version_py:
        errors.append("client.VERSION does not match metadata version")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build the CoworkingView QGIS plugin zip.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="zip path to write")
    args = parser.parse_args(argv)
    path = build(args.output)
    errors = validate(path)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
