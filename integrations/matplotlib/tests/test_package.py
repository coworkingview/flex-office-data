"""Packaging metadata, the README figure, and the release workflow."""

from __future__ import annotations

import importlib.util
import os

import matplotlib.pyplot as plt
import pytest
import tomllib

import mpl_coworkingview as cv
from mpl_coworkingview._version import __version__

from .conftest import REPO


def test_version_and_project_urls() -> None:
    pyproject = tomllib.loads((REPO / "integrations" / "matplotlib" / "pyproject.toml").read_text())
    project = pyproject["project"]
    assert project["name"] == "mpl-coworkingview"
    assert project["version"] == __version__ == "0.1.0"
    assert project["license"] == "MIT"
    assert "Framework :: Matplotlib" in project["classifiers"]
    urls = project["urls"]
    assert urls["Homepage"] == "https://coworkingview.com"
    assert urls["Source"] == "https://github.com/coworkingview/flex-office-data"
    assert urls["Documentation"].endswith("/integrations/matplotlib#readme")
    assert "requests" not in project["dependencies"]
    assert any(item.startswith("matplotlib") for item in project["dependencies"])


def test_readme_figure_is_a_png_of_the_fixture() -> None:
    image = REPO / "integrations" / "matplotlib" / "docs" / "example.png"
    assert image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    readme = (REPO / "integrations" / "matplotlib" / "README.md").read_text(encoding="utf-8")
    assert "docs/example.png" in readme
    assert "Data: CoworkingView Price Index (CC BY 4.0)" in readme


def test_render_example_script_is_offline(tmp_path) -> None:
    path = REPO / "integrations" / "matplotlib" / "tools" / "render_example.py"
    spec = importlib.util.spec_from_file_location("render_example", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    out = tmp_path / "example.png"
    module.render(out)
    assert out.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")


def test_release_workflow_and_ci_job() -> None:
    release = (REPO / ".github" / "workflows" / "mpl-release.yml").read_text(encoding="utf-8")
    assert "mpl-v*" in release
    assert "workflow_dispatch" in release
    assert "id-token: write" in release
    assert "environment: pypi" in release
    assert "pypa/gh-action-pypi-publish@release/v1" in release
    assert "integrations/matplotlib/dist/" in release
    ci = (REPO / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    assert "mpl-coworkingview" in ci


def test_import_exports() -> None:
    assert cv.ATTRIBUTION.startswith("Data: CoworkingView Price Index")
    assert callable(cv.plot_city_rates)
    assert callable(cv.plot_rate_comparison)


@pytest.mark.live
@pytest.mark.skipif(
    os.environ.get("COWORKINGVIEW_LIVE_TESTS") != "1",
    reason="live API tests are opt-in (COWORKINGVIEW_LIVE_TESTS=1)",
)
def test_live_berlin_chart() -> None:
    _fig, ax = plt.subplots()
    bars = cv.plot_city_rates(ax, "berlin", locale="en")
    assert len(bars) >= 1
    assert ax.get_xlabel() == cv.ATTRIBUTION
    labels = [tick.get_text() for tick in ax.get_xticklabels()]
    assert "flex_desk" in labels
