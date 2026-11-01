import XCTest
@testable import CoworkingView

final class GoldenTests: XCTestCase {
    func testRatesMatchGolden() throws {
        let dataset = try Parser.rates(envelope: try JSON.parse(fixture("market_rates.json")))
        assertSameText(ratesCSV(dataset.data), try fixtureText("rates.csv"))
        XCTAssertTrue(dataset.attribution?.contains("CoworkingView Price Index") == true)
        XCTAssertEqual(dataset.license, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(dataset.asOf, "2026-10-27T21:06:48.313Z")
        XCTAssertEqual(dataset.data.map(\.citySlug).contains("example-town"), false)
    }

    func testCitiesMatchGolden() throws {
        let dataset = try Parser.cities(envelope: try JSON.parse(fixture("market_rates.json")))
        assertSameText(citiesCSV(dataset.data), try fixtureText("cities.csv"))
        XCTAssertEqual(dataset.data.last?.citySlug, "example-town")
        XCTAssertEqual(dataset.data.last?.published, false)
    }

    func testSpacesMatchGolden() throws {
        let page = try Parser.properties(envelope: try JSON.parse(fixture("properties_berlin.json")), locale: "en")
        assertSameText(listingsCSV(page.rows), try fixtureText("spaces.csv"))
        XCTAssertEqual(page.total, 110)
        XCTAssertEqual(
            page.attribution,
            "Source: CoworkingView — Coworking spaces in Berlin, https://coworkingview.com/en/coworking/berlin."
        )
        XCTAssertTrue(page.notice?.contains("not permitted") == true)
    }

    func testSpacePricingMatchesGolden() throws {
        let space = try Parser.space(envelope: try JSON.parse(fixture("property_detail.json")), locale: "en")
        assertSameText(pricingCSV(space.pricing), try fixtureText("space_pricing.csv"))
        XCTAssertEqual(space.amenities.count, 9)
        XCTAssertEqual(space.marketVerdict, "around")
        XCTAssertEqual(space.marketMedianText, "214")
        XCTAssertNil(space.capacity)
        XCTAssertNil(space.pricing[1].price)
        XCTAssertNil(space.pricing[1].currency)
        XCTAssertTrue(space.pricing[1].priceOnRequest)
        XCTAssertEqual(space.pricing[0].priceText, "209")
        let encoded = String(decoding: try JSONEncoder().encode(space), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Example description"))
        XCTAssertFalse(encoded.contains("example.com"))
        XCTAssertNotNil(space.attribution)
        XCTAssertNotNil(space.notice)
    }

    func testListingURLsFollowLocale() throws {
        let envelope = try JSON.parse(fixture("properties_berlin.json"))
        let spanish = try Parser.properties(envelope: envelope, locale: "es").rows[0]
        let german = try Parser.properties(envelope: envelope, locale: "de").rows[0]
        XCTAssertTrue(spanish.url.hasPrefix("https://coworkingview.com/es/oficina/"))
        XCTAssertTrue(german.url.hasPrefix("https://coworkingview.com/de/buero/"))
    }

    func testConvertedCurrencyParses() throws {
        let rates = try Parser.rates(envelope: try JSON.parse(fixture("market_rates_berlin_usd.json"))).data
        XCTAssertFalse(rates.isEmpty)
        for rate in rates {
            XCTAssertEqual(rate.currency, "USD")
            XCTAssertEqual(rate.citySlug, "berlin")
        }
        XCTAssertEqual(rates[0].product, "flex_desk")
        XCTAssertEqual(rates[0].unit, "month")
        XCTAssertTrue(rates.contains { $0.product == "day_pass" && $0.unit == "day" })
        XCTAssertTrue(rates.contains { $0.product == "meeting_room" && $0.unit == "hour" })
    }

    func testEmptySearchParses() throws {
        let page = try Parser.properties(envelope: try JSON.parse(fixture("properties_empty.json")), locale: "en")
        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertEqual(listingsCSV(page.rows).split(separator: "\n").count, 1)
        XCTAssertEqual(page.total, 0)
    }

    func testNewAggregateAppearsWithoutACodeChange() throws {
        let body = """
        {"data":{"asOf":"2026-01-01T00:00:00Z","cities":[{"city":{"slug":"berlin","name":"Berlin"},"currency":"EUR","figures":[],"eventSpace":{"median":{"amount":100},"sampleSize":3},"rooftopBar":{"median":{"amount":12.5},"sampleSize":11}}]}}
        """
        let rates = try Parser.rates(envelope: try JSON.parse(body)).data
        XCTAssertEqual(rates.map(\.product), ["event_space", "rooftop_bar"])
        XCTAssertEqual(rates[0].unit, "hour")
        XCTAssertEqual(rates[0].medianText, "100")
        XCTAssertNil(rates[0].p25)
        XCTAssertTrue(rates[0].lowConfidence)
        XCTAssertNil(rates[1].unit)
        XCTAssertEqual(rates[1].medianText, "12.5")
        XCTAssertFalse(rates[1].lowConfidence)
    }

    func testEmptyFiguresFallsThroughToByType() throws {
        let body = """
        {"data":{"asOf":"t","cities":[{"city":{"slug":"berlin","name":"Berlin"},"currency":"EUR","figures":[],"byType":[{"optionType":"fix_desk","median":{"amount":10},"sampleSize":4}]}]}}
        """
        let rates = try Parser.rates(envelope: try JSON.parse(body)).data
        XCTAssertEqual(rates.count, 1)
        XCTAssertEqual(rates[0].product, "fix_desk")
        XCTAssertEqual(rates[0].unit, "month")
        XCTAssertTrue(rates[0].lowConfidence)
    }

    func testFutureAggregatesSortWithUnknownProducts() throws {
        let body = """
        {"data":{"asOf":"2026-10-27T00:00:00Z","cities":[{"city":{"slug":"zurich","name":"Zurich"},"currency":"CHF","figures":[],"byType":[{"optionType":"private_office","median":{"amount":900},"sampleSize":12},{"optionType":"flex_desk","median":{"amount":400},"sampleSize":4}],"eventSpace":{"median":{"amount":150},"p25":{"amount":100},"p75":{"amount":200},"sampleSize":3},"virtualOffice":{"median":{"amount":60},"sampleSize":20},"parkingSpot":{"median":{"amount":120},"sampleSize":5},"aRooftop":{"median":{"amount":10},"sampleSize":1},"p25":{"amount":1},"insufficientData":false}],"unpublished":[{"city":{"slug":"bern","name":"Bern"}}]}}
        """
        let rates = try Parser.rates(envelope: try JSON.parse(body)).data
        let got = rates.map {
            "\($0.product)|\($0.unit ?? "")|\($0.medianText)|\($0.p25Text ?? "")|\($0.lowConfidence)"
        }
        XCTAssertEqual(
            got,
            [
                "flex_desk|month|400||true",
                "private_office|month|900||false",
                "event_space|hour|150|100|true",
                "virtual_office|month|60||false",
                "a_rooftop||10||true",
                "parking_spot||120||true",
            ]
        )
        XCTAssertEqual(Set(rates.map(\.citySlug)), ["zurich"])
        XCTAssertNil(rates[0].countryCode)
        XCTAssertNil(rates[0].propertyCount)
    }

    func testSnakeCase() {
        XCTAssertEqual(Parser.snake("dayPass"), "day_pass")
        XCTAssertEqual(Parser.snake("eventSpace"), "event_space")
        XCTAssertEqual(Parser.snake("x"), "x")
    }

    func testCodableUsesSpecColumnNames() throws {
        let rate = try Parser.rates(envelope: try JSON.parse(fixture("market_rates.json"))).data[0]
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rate)) as? [String: Any]
        XCTAssertEqual(object?["city_slug"] as? String, rate.citySlug)
        XCTAssertEqual(object?["low_confidence"] as? Bool, rate.lowConfidence)
        XCTAssertNil(object?["medianText"])
        XCTAssertNil(object?["citySlug"])
    }
}
