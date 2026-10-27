"""Find meeting rooms and event spaces in a city.

    python examples/meeting_and_event_spaces.py madrid

Two small requests (one per product). Each space links to its listing page,
where prices and booking details live.
"""

from __future__ import annotations

import sys

import coworkingview as cwv


def main(city: str = "berlin") -> None:
    for product, label in (("meeting_room", "Meeting rooms"), ("event_space", "Event spaces")):
        found = cwv.spaces(city=city, product=product, sort="price-asc", limit=10)
        total = found.attrs.get("total")
        print(f"\n{label} in {city}: showing {len(found)} of {total if total is not None else '?'}")
        for row in found.to_dict("records"):
            where = row["zone_slug"] if isinstance(row["zone_slug"], str) else "-"
            print(f"  {row['title']:<55.55} {where:<22} {row['url']}")
        if not found.empty:
            print(f"  {found.attrs['attribution']}")


if __name__ == "__main__":
    main(*sys.argv[1:2])
