"""Airflow 2 and Airflow 3 imports for the hook and operator."""

from __future__ import annotations

try:  # Airflow 3
    from airflow.sdk import BaseHook
except ImportError:  # Airflow 2
    from airflow.hooks.base import BaseHook  # type: ignore[no-redef,attr-defined]

try:  # Airflow 3
    from airflow.sdk import BaseOperator
except ImportError:  # Airflow 2
    from airflow.models import BaseOperator  # type: ignore[no-redef,assignment]

__all__ = ["BaseHook", "BaseOperator"]
