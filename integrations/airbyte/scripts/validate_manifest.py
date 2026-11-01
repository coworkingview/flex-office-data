#!/usr/bin/env python3
"""Run source-declarative-manifest spec, check, discover and read against the live API.

Uses the airbyte-cdk YamlDeclarativeSource, which is what
``source-declarative-manifest`` loads for a manifest shipped in the connector
image. Prints a short JSON summary on stdout.
"""

from __future__ import annotations

import json
import logging
import sys
import tempfile
from collections import Counter
from dataclasses import asdict
from enum import Enum
from pathlib import Path

from airbyte_cdk.models import (
    AirbyteMessage,
    AirbyteStream,
    ConfiguredAirbyteCatalog,
    ConfiguredAirbyteStream,
    DestinationSyncMode,
    Status,
    SyncMode,
    Type,
)
from airbyte_cdk.sources.declarative.yaml_declarative_source import YamlDeclarativeSource
from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1] / "source-coworkingview"
MANIFEST = ROOT / "manifest.yaml"
CONFIG = {"city": "berlin", "locale": "en"}
INVALID = {"city": "berlin", "locale": "fr"}
EMPTY: dict[str, str] = {}


def source(config: dict, catalog: ConfiguredAirbyteCatalog | None = None) -> YamlDeclarativeSource:
    return YamlDeclarativeSource(
        path_to_yaml=str(MANIFEST),
        config=config,
        catalog=catalog,
    )


def configured_catalog(streams: list[AirbyteStream]) -> ConfiguredAirbyteCatalog:
    return ConfiguredAirbyteCatalog(
        streams=[
            ConfiguredAirbyteStream(
                stream=stream,
                sync_mode=SyncMode.full_refresh,
                destination_sync_mode=DestinationSyncMode.overwrite,
            )
            for stream in streams
        ]
    )


def to_jsonable(value):
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, dict):
        return {key: to_jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_jsonable(item) for item in value]
    return value


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger("source-coworkingview")
    summary: dict = {"manifest": str(MANIFEST)}

    spec = source(CONFIG).spec(logger)
    connection_spec = spec.connectionSpecification
    summary["spec_properties"] = sorted(connection_spec["properties"])
    summary["spec_defaults"] = {
        name: field.get("default")
        for name, field in connection_spec["properties"].items()
    }

    ok = source(CONFIG).check(logger, CONFIG)
    empty = source(EMPTY).check(logger, EMPTY)
    bad = source(INVALID).check(logger, INVALID)
    summary["check"] = {
        "berlin": ok.status.value if isinstance(ok.status, Status) else str(ok.status),
        "berlin_message": ok.message,
        "empty_config": empty.status.value if isinstance(empty.status, Status) else str(empty.status),
        "invalid_locale": bad.status.value if isinstance(bad.status, Status) else str(bad.status),
        "invalid_message": bad.message,
    }

    catalog = source(CONFIG).discover(logger, CONFIG)
    summary["streams"] = [
        {
            "name": stream.name,
            "primary_key": stream.source_defined_primary_key,
            "sync_modes": [mode.value if hasattr(mode, "value") else str(mode) for mode in stream.supported_sync_modes],
            "property_names": sorted((stream.json_schema or {}).get("properties", {})),
        }
        for stream in catalog.streams
    ]

    configured = configured_catalog(catalog.streams)
    catalog_path = ROOT / "integration_tests" / "configured_catalog.json"
    rendered = json.dumps(to_jsonable(asdict(configured)), indent=2) + "\n"
    if catalog_path.read_text() != rendered:
        summary["catalog_drift"] = True
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".json") as handle:
            handle.write(rendered)
            summary["catalog_rendered_to"] = handle.name
    else:
        summary["catalog_drift"] = False

    reader = source(CONFIG, configured)
    counts: Counter[str] = Counter()
    keys: dict[str, set[str]] = {}
    schema_errors: dict[str, list[str]] = {}
    forbidden = {"images", "excerpt", "logo"}
    samples: dict[str, dict] = {}
    attribution = None
    validators = {
        stream.name: Draft7Validator(stream.json_schema)
        for stream in catalog.streams
        if stream.json_schema
    }
    for message in reader.read(logger, CONFIG, configured, None):
        if not isinstance(message, AirbyteMessage):
            continue
        if message.type != Type.RECORD or message.record is None:
            continue
        name = message.record.stream
        data = message.record.data
        counts[name] += 1
        keys.setdefault(name, set()).update(data.keys())
        if name not in samples:
            samples[name] = data
        if name == "market_rates" and attribution is None:
            attribution = data.get("attribution")
        if forbidden & set(data.keys()) or (
            isinstance(data.get("operator"), dict) and "logo" in data["operator"]
        ):
            schema_errors.setdefault(name, []).append("operator media or excerpt was emitted")
        validator = validators.get(name)
        if validator is not None:
            for error in validator.iter_errors(data):
                schema_errors.setdefault(name, []).append(error.message)
                if len(schema_errors[name]) > 8:
                    break

    summary["read_counts"] = dict(counts)
    summary["record_keys"] = {name: sorted(found) for name, found in keys.items()}
    summary["schema_errors"] = {name: errs[:8] for name, errs in schema_errors.items()}
    summary["attribution_prefix"] = (attribution or "")[:180]
    summary["property_slugs"] = None
    rate = samples.get("market_rates") or {}
    summary["rate_city"] = (rate.get("city") or {}).get("slug")
    summary["rate_license"] = rate.get("license")
    # attribution may not be in the first 8 keys; check explicitly below
    print(json.dumps(summary, indent=2, default=str))
    failed = (
        summary["check"]["berlin"] != "SUCCEEDED"
        or summary["check"]["empty_config"] != "SUCCEEDED"
        or summary["check"]["invalid_locale"] != "FAILED"
        or counts.get("properties", 0) < 51
        or counts.get("market_rates", 0) != 1
        or schema_errors
        or summary.get("catalog_drift")
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
