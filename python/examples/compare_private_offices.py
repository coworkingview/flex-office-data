"""Compare private-office prices across cities with the CoworkingView Price Index.

    python examples/compare_private_offices.py            # every city, in EUR
    python examples/compare_private_offices.py GBP        # every city, in GBP

One request. Prints a ranked table; no plotting library needed.
"""

from __future__ import annotations

import sys

import coworkingview as cwv


def main(currency: str = "EUR") -> None:
    rates = cwv.rates(currency=currency)
    offices = rates[rates["product"] == "private_office"].sort_values("median", ascending=False)
    if offices.empty:
        print("No private-office figures published yet.")
        return

    top = float(offices["median"].max())
    print(f"Private office, median monthly price ({currency})\n")
    for row in offices.to_dict("records"):
        median = float(row["median"])
        bar = "#" * round(30 * median / top)
        flag = "  (low sample)" if row["low_confidence"] else ""
        print(f"{row['city_name']:<16} {median:>8,.0f}  {bar}{flag}  n={row['sample_size']}")

    # CC BY 4.0: the credit line travels with the data. Keep it with what you publish.
    print("\n" + rates.attrs["attribution"])


if __name__ == "__main__":
    main(*sys.argv[1:2])
