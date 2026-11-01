package com.coworkingview.eclipse;

/** Published desk ranges for one city. A missing product is null. */
public record CityPrice(
        String slug,
        String name,
        String countryCode,
        String currency,
        DeskQuote hotDesk,
        DeskQuote dedicatedDesk,
        DeskQuote privateOffice) {
}
