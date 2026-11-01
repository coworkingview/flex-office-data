// Copyright (c) 2026 CoworkingView. License: MIT.
import std.stdio : writefln, writeln;

import coworkingview : Client;

void main()
{
    auto client = new Client();
    auto berlin = client.rates(city: "berlin");
    foreach (rate; berlin.data)
    {
        writefln("%s %s %s %s n=%s", rate.product, rate.unit, rate.medianText,
            rate.currency, rate.sampleSize);
    }
    // Price Index figures are CC BY 4.0. Print this next to anything you republish.
    if (berlin.attribution.length)
        writeln(berlin.attribution);
}
