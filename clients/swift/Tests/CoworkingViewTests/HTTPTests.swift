import XCTest
@testable import CoworkingView

final class HTTPTests: XCTestCase {
    private let ratesOK = #"{"data":{"cities":[],"asOf":"2026-10-27T21:06:48.313Z"},"meta":{}}"#

    func testUserAgentAndAccept() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: ratesOK)]
        let client = try scriptedClient(transport: transport)
        _ = try await client.rates()
        let headers = try XCTUnwrap(transport.recorded().first).headers
        XCTAssertEqual(
            header(headers, "User-Agent"),
            "coworkingview-swift/\(Client.version) (+https://github.com/coworkingview/flex-office-data)"
        )
        XCTAssertEqual(header(headers, "Accept"), "application/json")
    }

    func testCustomUserAgent() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: ratesOK)]
        let client = try Client(
            baseURL: Client.defaultBaseURL,
            timeout: 20,
            userAgent: "my-app/1.0",
            locale: "en",
            environment: [:],
            transport: transport,
            sleeper: RecordingSleeper()
        )
        _ = try await client.rates()
        XCTAssertEqual(header(transport.recorded()[0].headers, "User-Agent"), "my-app/1.0")
    }

    func testRetriesOnceThenSucceeds() async throws {
        for status in [429, 500, 502, 503] {
            let transport = FakeTransport()
            let sleeper = RecordingSleeper()
            transport.queued = [
                httpResponse(status: status, body: #"{"title":"busy"}"#),
                httpResponse(body: ratesOK),
            ]
            let client = try scriptedClient(transport: transport, sleeper: sleeper)
            let dataset = try await client.rates()
            XCTAssertTrue(dataset.data.isEmpty)
            XCTAssertEqual(transport.recorded().count, 2)
            XCTAssertEqual(sleeper.recorded(), [2])
        }
    }

    func testRetriesOnlyOnce() async throws {
        let transport = FakeTransport()
        let sleeper = RecordingSleeper()
        transport.queued = [
            httpResponse(status: 503, body: #"{"title":"Down","code":"UNAVAILABLE"}"#),
            httpResponse(status: 503, body: #"{"title":"Still down","code":"UNAVAILABLE"}"#),
            httpResponse(body: ratesOK),
        ]
        let client = try scriptedClient(transport: transport, sleeper: sleeper)
        do {
            _ = try await client.rates()
            XCTFail("expected the second 503 to surface")
        } catch let error as APIError {
            XCTAssertEqual(transport.recorded().count, 2)
            XCTAssertEqual(error.status, 503)
            XCTAssertEqual(error.title, "Still down")
            XCTAssertEqual(sleeper.recorded().count, 1)
            XCTAssertEqual(error.message, "503 UNAVAILABLE: Still down")
        }
    }

    func testRetryAfterIsHonouredAndCapped() async throws {
        let transport = FakeTransport()
        let sleeper = RecordingSleeper()
        transport.queued = [
            httpResponse(status: 429, body: "{}", headers: ["Retry-After": "3"]),
            httpResponse(body: ratesOK),
            httpResponse(status: 429, body: "{}", headers: ["Retry-After": "120", "RateLimit-Reset": "5"]),
            httpResponse(body: ratesOK),
            httpResponse(status: 429, body: "{}", headers: ["RateLimit-Reset": "4"]),
            httpResponse(body: ratesOK),
        ]
        let client = try scriptedClient(transport: transport, sleeper: sleeper)
        _ = try await client.rates()
        _ = try await client.rates()
        _ = try await client.rates()
        XCTAssertEqual(sleeper.recorded(), [3, 10, 4])
    }

    func testRetryWaitHeaderParsing() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = now.addingTimeInterval(6)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let soonHeader = formatter.string(from: soon)
        let waited = RetryDelay.seconds(headers: ["Retry-After": soonHeader], now: now)
        XCTAssertGreaterThanOrEqual(waited, 4)
        XCTAssertLessThanOrEqual(waited, 6)
        let past = formatter.string(from: now.addingTimeInterval(-300))
        XCTAssertEqual(RetryDelay.seconds(headers: ["Retry-After": past], now: now), 0)
        XCTAssertEqual(
            RetryDelay.seconds(headers: ["Retry-After": "soon", "RateLimit-Reset": "1.5"], now: now),
            1.5
        )
        XCTAssertEqual(RetryDelay.seconds(headers: ["Retry-After": "-3"], now: now), 0)
        XCTAssertEqual(RetryDelay.seconds(headers: [:], now: now), 2)
        XCTAssertEqual(
            RetryDelay.seconds(headers: ["Retry-After": "Tue, 27 Oct 2099 21:00:00"], now: now),
            RetryDelay.maximum
        )
    }

    func testProblemJSONBecomesAPIError() async throws {
        let transport = FakeTransport()
        transport.queued = [
            httpResponse(
                status: 404,
                body: """
                {"type":"https://coworkingview.com/problems/not-found","title":"Not found","status":404,"code":"NOT_FOUND","detail":"No property with slug 'nope'."}
                """
            ),
        ]
        do {
            _ = try await scriptedClient(transport: transport).space(slug: "nope")
            XCTFail("expected 404")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.code, "NOT_FOUND")
            XCTAssertEqual(error.title, "Not found")
            XCTAssertEqual(error.detail, "No property with slug 'nope'.")
            XCTAssertTrue(error.errors.isEmpty)
            XCTAssertTrue(String(describing: error).contains("404 NOT_FOUND: Not found"))
        }
    }

    func testValidationProblemFixture() async throws {
        let body = String(decoding: try fixture("error_validation.json"), as: UTF8.self)
        let transport = FakeTransport()
        transport.queued = [httpResponse(status: 400, body: body)]
        do {
            _ = try await scriptedClient(transport: transport).rates(currency: "VES")
            XCTFail("expected validation failure")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.code, "VALIDATION_FAILED")
            XCTAssertEqual(error.errors.first?.path, "currency")
        }
    }

    func testNonJSONErrorFallsBackToReason() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(status: 403, body: "<html>Forbidden</html>")]
        do {
            _ = try await scriptedClient(transport: transport).rates()
            XCTFail("expected 403")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
            XCTAssertEqual(error.code, "HTTP_403")
            XCTAssertEqual(error.title, "Forbidden")
            XCTAssertNil(error.detail)
        }
    }

    func testNonJSONSuccessIsBadResponse() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: "<html>maintenance</html>")]
        do {
            _ = try await scriptedClient(transport: transport).rates()
            XCTFail("expected bad response")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "BAD_RESPONSE")
            XCTAssertEqual(error.status, 200)
        }
    }

    func testJSONThatIsNotAnObjectIsBadResponse() async throws {
        let transport = FakeTransport()
        transport.queued = [httpResponse(body: "[1,2,3]")]
        do {
            _ = try await scriptedClient(transport: transport).rates()
            XCTFail("expected bad response")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "BAD_RESPONSE")
            XCTAssertEqual(error.title, "The API returned JSON that is not an object")
        }
    }

    func testUnexpectedEnvelopeIsBadResponse() async throws {
        let cases = [
            (#"{"meta":{}}"#, "rates"),
            (#"{"data":[]}"#, "rates"),
            (#"{"data":{}}"#, "spaces"),
            (#"{"data":[]}"#, "space"),
        ]
        for (body, call) in cases {
            let transport = FakeTransport()
            transport.queued = [httpResponse(body: body)]
            let client = try scriptedClient(transport: transport)
            do {
                switch call {
                case "spaces": _ = try await client.spaces()
                case "space": _ = try await client.space(slug: "x")
                default: _ = try await client.rates()
                }
                XCTFail("expected \(call) to reject \(body)")
            } catch let error as APIError {
                XCTAssertEqual(error.code, "BAD_RESPONSE")
            }
        }
    }

    func testUnreachableHostRaisesBaseError() async throws {
        let transport = FakeTransport()
        transport.failure = TransportFailure(message: "connection refused")
        do {
            _ = try await scriptedClient(transport: transport).rates()
            XCTFail("expected a connection error")
        } catch let error as APIError {
            XCTFail("connection failures are not API errors: \(error)")
        } catch let error as CoworkingViewError {
            XCTAssertTrue(error.message.contains("Could not reach"))
            XCTAssertTrue(error.message.contains("connection refused"))
        }
    }
}
