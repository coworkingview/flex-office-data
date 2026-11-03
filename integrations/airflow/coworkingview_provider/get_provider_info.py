"""Provider metadata Airflow reads at startup.

This module must stay free of ``airflow`` imports. Airflow calls
:func:`get_provider_info` while discovering installed providers, and the hook
module is imported later, only when a connection or a task needs it.
"""

from __future__ import annotations

from typing import Any

from coworkingview_provider._version import __version__


def get_provider_info() -> dict[str, Any]:
    """Return the provider dictionary described by Airflow's provider schema."""
    return {
        "package-name": "airflow-provider-coworkingview",
        "name": "CoworkingView",
        "description": (
            "Read the public `CoworkingView Price Index "
            "<https://coworkingview.com/en/tools/price-index>`_ for one city. "
            "``CoworkingViewHook`` calls ``GET /v1/market/rates``. "
            "``CoworkingViewRatesOperator`` returns those rates through XCom "
            "and can write the same JSON document to a file. "
            "The API is public and needs no key. The index is CC BY 4.0; "
            "the attribution string travels with the result."
        ),
        "versions": [__version__],
        "integrations": [
            {
                "integration-name": "CoworkingView",
                "external-doc-url": "https://coworkingview.com/en/tools/price-index",
                "tags": ["service"],
            }
        ],
        "connection-types": [
            {
                "connection-type": "coworkingview",
                "hook-class-name": ("coworkingview_provider.hooks.coworkingview.CoworkingViewHook"),
                "hook-name": "CoworkingView",
                # Airflow 3 builds the connection form from this block.
                # Airflow 2 uses CoworkingViewHook.get_ui_field_behaviour().
                "ui-field-behaviour": {
                    "hidden-fields": ["schema", "login", "password", "port", "extra"],
                    "relabeling": {"host": "API base URL (optional)"},
                    "placeholders": {"host": "https://api.coworkingview.com"},
                },
            }
        ],
        "hooks": [
            {
                "integration-name": "CoworkingView",
                "python-modules": ["coworkingview_provider.hooks.coworkingview"],
            }
        ],
        "operators": [
            {
                "integration-name": "CoworkingView",
                "python-modules": ["coworkingview_provider.operators.rates"],
            }
        ],
    }
