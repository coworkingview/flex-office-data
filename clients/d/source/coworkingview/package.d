// Copyright (c) 2026 CoworkingView. License: MIT.
/**
Client for the public CoworkingView API (`https://api.coworkingview.com`).

No API key. Importing this module does not open a socket. Price Index figures
(`Client.rates`, `Client.cities`) are CC BY 4.0 and carry the response's
attribution. Catalogue search (`Client.spaces`, `Client.space`) omits operator
descriptions, photos and logos.

See_Also: https://coworkingview.com/en/api
*/
module coworkingview;

public import coworkingview.client;
public import coworkingview.error;
public import coworkingview.http;
public import coworkingview.model;
