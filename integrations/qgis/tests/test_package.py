# -*- coding: utf-8 -*-
"""Package checks for the QGIS plugin zip and metadata."""

import ast
import configparser
import py_compile
import tempfile
import unittest
from pathlib import Path

import build

PLUGIN = Path(__file__).resolve().parents[1] / "coworkingview"


class PackageTests(unittest.TestCase):
    def test_sources_compile(self):
        for path in sorted(PLUGIN.glob("*.py")):
            py_compile.compile(str(path), doraise=True)

    def test_qgis_modules_do_not_run_at_import_of_client(self):
        source = (PLUGIN / "__init__.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        for node in tree.body:
            self.assertNotIsInstance(node, (ast.Import, ast.ImportFrom))

    def test_metadata_file(self):
        parser = configparser.ConfigParser()
        parser.optionxform = str
        parser.read(PLUGIN / "metadata.txt", encoding="utf-8")
        general = dict(parser.items("general"))
        self.assertEqual(general["name"], "CoworkingView")
        self.assertEqual(general["qgisMinimumVersion"], "3.22")
        self.assertEqual(general["version"], "0.1.0")
        self.assertEqual(general["author"], "CoworkingView")
        self.assertEqual(general["email"], "info@coworkingview.com")
        self.assertEqual(general["homepage"], "https://coworkingview.com")
        self.assertNotIn("www.", general["homepage"])
        self.assertTrue(general["about"])
        self.assertTrue(general["description"])
        self.assertNotIn("<", general["about"])
        self.assertIn("coworking", general["tags"])

    def test_readme_covers_install_and_the_open_action(self):
        text = (PLUGIN / "README.md").read_text(encoding="utf-8")
        self.assertIn("Install from ZIP", text)
        self.assertIn("Open on CoworkingView", text)
        self.assertIn("3.22", text)
        self.assertIn("GPL-2.0-or-later", text)
        self.assertIn("name", text)
        self.assertIn("address", text)

    def test_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = build.build(Path(tmp) / "coworkingview.zip")
            errors = build.validate(path)
            self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
