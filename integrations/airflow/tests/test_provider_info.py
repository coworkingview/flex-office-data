"""Provider metadata matches Airflow's entry-point contract."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from coworkingview_provider import __version__
from coworkingview_provider.get_provider_info import get_provider_info

ROOT = Path(__file__).resolve().parents[1]
HOOK = "coworkingview_provider.hooks.coworkingview.CoworkingViewHook"


def test_provider_info_declares_the_hook_and_operator():
    info = get_provider_info()
    assert info["package-name"] == "airflow-provider-coworkingview"
    assert info["name"] == "CoworkingView"
    assert info["description"]
    assert info["versions"] == [__version__] == ["0.1.0"]
    connection = info["connection-types"][0]
    assert connection["connection-type"] == "coworkingview"
    assert connection["hook-class-name"] == HOOK
    assert "password" in connection["ui-field-behaviour"]["hidden-fields"]
    assert info["hooks"][0]["python-modules"] == ["coworkingview_provider.hooks.coworkingview"]
    assert info["operators"][0]["python-modules"] == ["coworkingview_provider.operators.rates"]
    assert info["integrations"][0]["integration-name"] == "CoworkingView"
    assert info["integrations"][0]["external-doc-url"].startswith("https://coworkingview.com/")


def test_pyproject_urls_and_entry_point():
    text = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    assert 'name = "airflow-provider-coworkingview"' in text
    assert 'version = "0.1.0"' in text
    assert 'license = "MIT"' in text
    assert 'Homepage = "https://coworkingview.com"' in text
    assert 'Source = "https://github.com/coworkingview/flex-office-data"' in text
    assert 'provider_info = "coworkingview_provider.get_provider_info:get_provider_info"' in text


def test_metadata_import_does_not_import_airflow():
    script = (
        "import sys\n"
        "import coworkingview_provider.get_provider_info as info\n"
        "assert 'airflow' not in sys.modules\n"
        "assert info.get_provider_info()['package-name'] == 'airflow-provider-coworkingview'\n"
    )
    subprocess.check_call([sys.executable, "-c", script])
