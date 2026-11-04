#!/usr/bin/env python3
"""Ask the GitHub API to make the cwv Helm OCI package public.

Uses GITHUB_TOKEN. Prints statuses and short JSON fields only, never the token.
Exits 0 either way: publishing the chart must not depend on a visibility change
the token may be forbidden to make. The caller reads "Package visibility:".
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request

TOKEN = os.environ["GITHUB_TOKEN"]
OWNER = os.environ["GITHUB_REPOSITORY_OWNER"]
HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {TOKEN}",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "coworkingview-helm-release",
}


def call(method: str, url: str, body: dict | None = None) -> tuple[int, str]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode()


def brief(raw: str) -> str:
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError:
        return raw[:400]
    if isinstance(doc, dict):
        keep = {
            key: doc.get(key)
            for key in ("name", "visibility", "message", "status", "html_url")
            if key in doc
        }
        return json.dumps(keep)
    if isinstance(doc, list):
        rows = [
            {"name": item.get("name"), "visibility": item.get("visibility")}
            for item in doc
            if isinstance(item, dict)
        ]
        return json.dumps(rows)
    return raw[:400]


def main() -> None:
    list_url = (
        f"https://api.github.com/orgs/{OWNER}/packages"
        "?package_type=container&per_page=100"
    )
    status, raw = call("GET", list_url)
    print(f"GET {list_url} -> HTTP {status} {brief(raw)}")

    names = [
        "charts/cwv",
        "cwv",
        "flex-office-data/charts/cwv",
        "charts/cwv/cwv",
    ]
    try:
        listed = json.loads(raw)
    except json.JSONDecodeError:
        listed = []
    if isinstance(listed, list):
        for item in listed:
            name = item.get("name") if isinstance(item, dict) else None
            if name and name not in names:
                names.append(name)

    visibility = "unknown"
    for attempt in range(1, 5):
        for name in names:
            encoded = name.replace("/", "%2F")
            url = f"https://api.github.com/orgs/{OWNER}/packages/container/{encoded}"
            status, raw = call("PATCH", url, {"visibility": "public"})
            print(f"PATCH attempt {attempt} {name} -> HTTP {status} {brief(raw)}")
            if status == 200:
                try:
                    visibility = json.loads(raw).get("visibility", "unknown")
                except json.JSONDecodeError:
                    visibility = "unknown"
                break
        if visibility == "public":
            break
        time.sleep(5)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("### GHCR package visibility\n\n")
            handle.write(
                f"`ghcr.io/coworkingview/charts/cwv` visibility: `{visibility}`\n"
            )
    print(f"Package visibility: {visibility}")
    if visibility != "public":
        print(
            "::warning::GITHUB_TOKEN could not make ghcr.io/coworkingview/charts/cwv "
            "public. The chart was still pushed. An owner must set the package to "
            "public; the packages API did not accept this token."
        )


if __name__ == "__main__":
    main()
