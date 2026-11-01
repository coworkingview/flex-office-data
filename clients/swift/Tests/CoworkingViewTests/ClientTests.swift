import XCTest
@testable import CoworkingView

final class ClientTests: XCTestCase {
    func testRatesQueryParameters() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: #"{"data":{"cities":[]}}"#)]
        let client = try scriptedClient(transport: transport)
        _ = try await client.rates(city: "berlin", country: "DE", currency: "eur", locale: "de")
        let call = try XCTUnwrap(transport.recorded().first)
        XCTAssertEqual(call.url.path, "/v1/market/rates")
        XCTAssertEqual(
            queryItems(call.url),
            ["locale": "de", "city": "berlin", "country": "DE", "currency": "EUR"]
        )
    }

    func testSpacesQueryParameters() async throws {
        let transport = FakeTransport()
        transport.responder = pageResponder(total: 1)
        let client = try scriptedClient(transport: transport)
        _ = try await client.spaces(
            city: "berlin",
            country: "DE",
            zone: "mitte",
            operator: "regus",
            product: "meeting_room",
            minCapacity: 8,
            minPrice: 10,
            maxPrice: 99.5,
            currency: "EUR",
            sort: "price-asc",
            limit: 10,
            locale: "es"
        )
        let call = try XCTUnwrap(transport.recorded().first)
        XCTAssertEqual(call.url.path, "/v1/properties")
        XCTAssertEqual(
            queryItems(call.url),
            [
                "locale": "es",
                "city": "berlin",
                "country": "DE",
                "zone": "mitte",
                "operator": "regus",
                "pricingOptionType": "meeting_room",
                "minCapacity": "8",
                "minPrice": "10",
                "maxPrice": "99.5",
                "currency": "EUR",
                "sortBy": "price-asc",
                "page": "1",
                "pageSize": "10",
            ]
        )
    }

    func testSpacesPaginatesAndReusesSeed() async throws {
        let transport = FakeTransport()
        transport.responder = pageResponder(total: 500)
        let client = try scriptedClient(transport: transport)
        let dataset = try await client.spaces(limit: 120)
        XCTAssertEqual(dataset.data.map(\.slug), (0..<120).map { "space-\($0)" })
        let pages = transport.recorded().map { queryItems($0.url)["page"] }
        XCTAssertEqual(pages, ["1", "2", "3"])
        XCTAssertTrue(transport.recorded().allSatisfy { queryItems($0.url)["pageSize"] == "50" })
        XCTAssertNil(queryItems(transport.recorded()[0].url)["seed"])
        XCTAssertEqual(queryItems(transport.recorded()[1].url)["seed"], "43")
        XCTAssertEqual(queryItems(transport.recorded()[2].url)["seed"], "43")
        XCTAssertEqual(dataset.attribution, "citation page 1")
        XCTAssertEqual(dataset.notice, "notice")
        XCTAssertEqual(dataset.total, 500)
    }

    func testSpacesNoSeedUnlessRandom() async throws {
        let transport = FakeTransport()
        transport.responder = pageResponder(total: 80)
        let client = try scriptedClient(transport: transport)
        let dataset = try await client.spaces(sort: "date-desc", limit: 200)
        XCTAssertEqual(dataset.data.count, 80)
        XCTAssertEqual(transport.recorded().count, 2)
        XCTAssertNil(queryItems(transport.recorded()[1].url)["seed"])
    }

    func testSpacesStopsAtPageCount() async throws {
        let transport = FakeTransport()
        transport.responder = pageResponder(total: 30)
        let client = try scriptedClient(transport: transport)
        let dataset = try await client.spaces(limit: 200)
        XCTAssertEqual(dataset.data.count, 30)
        XCTAssertEqual(transport.recorded().count, 1)
    }

    func testSmallLimitIsOneSmallPage() async throws {
        let transport = FakeTransport()
        transport.responder = pageResponder(total: 500)
        let client = try scriptedClient(transport: transport)
        let dataset = try await client.spaces(limit: 5)
        XCTAssertEqual(dataset.data.count, 5)
        XCTAssertEqual(transport.recorded().count, 1)
        XCTAssertEqual(queryItems(transport.recorded()[0].url)["pageSize"], "5")
    }

    func testSpacesNeverExceeds200() async throws {
        let transport = FakeTransport()
        transport.responder = pageResponder(total: 10_000)
        let client = try scriptedClient(transport: transport)
        let dataset = try await client.spaces(limit: 200)
        XCTAssertEqual(dataset.data.count, 200)
        XCTAssertEqual(transport.recorded().count, 4)
    }

    func testSpacesStopsWithoutPagination() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: #"{"data":[{"slug":"a","title":"A"}],"meta":{}}"#)]
        let client = try scriptedClient(transport: transport)
        let dataset = try await client.spaces()
        XCTAssertEqual(dataset.data.count, 1)
        XCTAssertNil(dataset.attribution)
        XCTAssertNil(dataset.notice)
        XCTAssertNil(dataset.total)
    }

    func testMinimalCardGivesNulls() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: #"{"data":[{"slug":"a","title":"A"}],"meta":{}}"#)]
        let row = try await scriptedClient(transport: transport).spaces().data[0]
        XCTAssertNil(row.citySlug)
        XCTAssertNil(row.zoneSlug)
        XCTAssertNil(row.operatorName)
        XCTAssertNil(row.lat)
        XCTAssertNil(row.featured)
        XCTAssertNil(row.marketVerdict)
        XCTAssertNil(row.updatedAt)
        XCTAssertEqual(row.url, "https://coworkingview.com/en/workspace/a")
    }

    func testLimitCapExplainsWhy() async throws {
        let client = try scriptedClient(transport: FakeTransport())
        for limit in [201, 1000] {
            do {
                _ = try await client.spaces(limit: limit)
                XCTFail("expected the limit to be rejected")
            } catch let error as CoworkingViewError {
                XCTAssertTrue(error.message.contains("maximum of 200"))
                XCTAssertTrue(error.message.contains("not bulk-copied"))
                XCTAssertFalse(error is APIError)
            }
        }
    }

    func testValidationMessages() async throws {
        let client = try scriptedClient(transport: FakeTransport())
        try await expectMessage(client, "locale='fr' is not supported") { _ = try await $0.spaces(locale: "fr") }
        try await expectMessage(client, "currency='JPY' is not supported") { _ = try await $0.spaces(currency: "JPY") }
        try await expectMessage(client, "product='desk' is not supported") { _ = try await $0.spaces(product: "desk") }
        try await expectMessage(client, "sort='price' is not supported") { _ = try await $0.spaces(sort: "price") }
        try await expectMessage(client, "limit must be a positive integer") { _ = try await $0.spaces(limit: 0) }
        try await expectMessage(client, "min_capacity must be a non-negative integer") {
            _ = try await $0.spaces(minCapacity: -1)
        }
        try await expectMessage(client, "min_price must be a non-negative number") {
            _ = try await $0.spaces(minPrice: -1)
        }
        try await expectMessage(client, "min_price (100) is greater than max_price (50)") {
            _ = try await $0.spaces(minPrice: 100, maxPrice: 50)
        }
        try await expectMessage(client, "city must be a non-empty string") { _ = try await $0.spaces(city: "  ") }
        try await expectMessage(client, "locale='EN' is not supported") { _ = try await $0.rates(locale: "EN") }
        try await expectMessage(client, "currency='BTC' is not supported") { _ = try await $0.rates(currency: "BTC") }
        try await expectMessage(client, "country must be a non-empty string") { _ = try await $0.rates(country: "  ") }
    }

    func testVesIsPassedThrough() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: #"{"data":{"cities":[]}}"#)]
        _ = try await scriptedClient(transport: transport).rates(currency: "VES")
        XCTAssertEqual(queryItems(transport.recorded()[0].url)["currency"], "VES")
    }

    func testSlugIsRejectedBeforeARequest() async throws {
        let transport = FakeTransport()
        let client = try scriptedClient(transport: transport)
        do {
            _ = try await client.space(slug: "../etc")
            XCTFail("expected an invalid slug to fail")
        } catch let error as CoworkingViewError {
            XCTAssertTrue(error.message.contains("not a valid slug"))
        }
        XCTAssertTrue(transport.recorded().isEmpty)
    }

    func testExplicitBaseURLBeatsEnvironment() throws {
        let explicit = try Client(
            baseURL: URL(string: "http://arg.invalid"),
            timeout: 5,
            userAgent: nil,
            locale: "en",
            environment: [Client.baseURLEnvironment: "http://env.invalid"],
            transport: FakeTransport(),
            sleeper: RecordingSleeper()
        )
        XCTAssertEqual(explicit.baseURL.absoluteString, "http://arg.invalid")
        let fromEnv = try Client(
            baseURL: nil,
            timeout: 20,
            userAgent: "  ",
            locale: "de",
            environment: [Client.baseURLEnvironment: "http://env.example/"],
            transport: FakeTransport(),
            sleeper: RecordingSleeper()
        )
        XCTAssertEqual(fromEnv.baseURL.absoluteString, "http://env.example")
        XCTAssertEqual(fromEnv.userAgent, Client.defaultUserAgent)
        XCTAssertEqual(fromEnv.locale, "de")
        let fallback = try Client(
            baseURL: nil,
            timeout: 20,
            userAgent: nil,
            locale: "en",
            environment: [:],
            transport: FakeTransport(),
            sleeper: RecordingSleeper()
        )
        XCTAssertEqual(fallback.baseURL, Client.defaultBaseURL)
        XCTAssertTrue(fallback.description.contains("https://api.coworkingview.com"))
    }

    func testCreatingAClientDoesNotSendARequest() throws {
        let transport = FakeTransport()
        _ = try scriptedClient(transport: transport)
        XCTAssertTrue(transport.recorded().isEmpty)
    }

    func testBadTimeout() {
        XCTAssertThrowsError(
            try Client(
                baseURL: nil,
                timeout: 0,
                userAgent: nil,
                locale: "en",
                environment: [:],
                transport: FakeTransport(),
                sleeper: RecordingSleeper()
            )
        )
    }
}

private func expectMessage(
    _ client: Client,
    _ fragment: String,
    _ body: (Client) async throws -> Void
) async throws {
    do {
        try await body(client)
        XCTFail("expected \(fragment)")
    } catch let error as CoworkingViewError {
        XCTAssertTrue(error.message.contains(fragment), error.message)
    }
}

private func pageResponder(total: Int, seed: Int = 42) -> @Sendable (FakeTransport.Call) -> HTTPResponse {
    { call in
        let query = queryItems(call.url)
        let page = Int(query["page"] ?? "1") ?? 1
        let size = Int(query["pageSize"] ?? "50") ?? 50
        let start = (page - 1) * size
        let end = min(start + size, total)
        let cards = (start..<end).map { index in
            #"{"slug":"space-\#(index)","title":"Space \#(index)","city":{"slug":"berlin"}}"#
        }.joined(separator: ",")
        let pageCount = size == 0 ? 0 : (total + size - 1) / size
        let body = """
        {"data":[\(cards)],"meta":{"pagination":{"page":\(page),"pageSize":\(size),"total":\(total),"pageCount":\(pageCount)},"seed":\(seed + page),"citation":{"text":"citation page \(page)"},"catalogueNotice":"notice"}}
        """
        return httpResponse(body: body)
    }
}
