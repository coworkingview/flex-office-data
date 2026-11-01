package com.coworkingview.eclipse;

import java.util.List;

/** Cities from one Price Index response, plus the credit line the API sent. */
public record PriceIndex(
        List<CityPrice> cities,
        String asOf,
        String attribution,
        String licenseUrl,
        Origin origin,
        String notice) {
}
