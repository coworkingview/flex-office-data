"""Environment for Airflow imports. Set before any test module imports Airflow."""

from __future__ import annotations

import os
from pathlib import Path

_HOME = Path("/tmp/airflow-coworkingview-tests")
_HOME.mkdir(parents=True, exist_ok=True)
(_HOME / "dags").mkdir(exist_ok=True)

_DB = f"sqlite:///{_HOME / 'airflow.db'}"

os.environ.setdefault("AIRFLOW_HOME", str(_HOME))
os.environ.setdefault("AIRFLOW__CORE__LOAD_EXAMPLES", "False")
os.environ.setdefault("AIRFLOW__CORE__UNIT_TEST_MODE", "True")
os.environ.setdefault("AIRFLOW__CORE__EXECUTOR", "SequentialExecutor")
os.environ.setdefault("AIRFLOW__CORE__DAGS_FOLDER", str(_HOME / "dags"))
os.environ.setdefault("AIRFLOW__CORE__SQL_ALCHEMY_CONN", _DB)
os.environ.setdefault("AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", _DB)
# Public test key from the Airflow documentation, not a secret.
os.environ.setdefault("AIRFLOW__CORE__FERNET_KEY", "ZmDfcTF7_60GrrY167zsiPd67pEvs0aGOv2oasOM1Pg=")
