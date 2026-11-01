import Foundation
import XCTest
@testable import CoworkingView

func fixture(_ name: String) throws -> Data {
    let bundle = Bundle.module
    let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        ?? bundle.url(forResource: name, withExtension: nil)
    guard let url else {
        throw NSError(domain: "CoworkingViewTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try Data(contentsOf: url)
}

func fixtureText(_ name: String) throws -> String {
    let data = try fixture(name)
    return String(decoding: data, as: UTF8.self)
}

func assertSameText(
    _ actual: String,
    _ expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual == expected { return }
    let left = expected.split(separator: "\n", omittingEmptySubsequences: false)
    let right = actual.split(separator: "\n", omittingEmptySubsequences: false)
    let count = min(left.count, right.count)
    for index in 0..<count where left[index] != right[index] {
        XCTFail(
            "line \(index + 1)\nexpected: \(left[index])\nactual:   \(right[index])",
            file: file,
            line: line
        )
        return
    }
    XCTFail("line count expected \(left.count) actual \(right.count)", file: file, line: line)
}

func csvLine(_ cells: [String?]) -> String {
    cells.map { escapeCSV($0 ?? "") }.joined(separator: ",")
}

func escapeCSV(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

func ratesCSV(_ rows: [Rate]) -> String {
    var lines = [
        "city_slug,city_name,country_code,currency,product,unit,median,p25,p75,sample_size,property_count,operator_count,low_confidence,as_of",
    ]
    for row in rows {
        lines.append(
            csvLine([
                row.citySlug,
                row.cityName,
                row.countryCode,
                row.currency,
                row.product,
                row.unit,
                row.medianText,
                row.p25Text,
                row.p75Text,
                String(row.sampleSize),
                row.propertyCount.map(String.init),
                row.operatorCount.map(String.init),
                row.lowConfidence ? "true" : "false",
                row.asOf,
            ])
        )
    }
    return lines.joined(separator: "\n") + "\n"
}

func citiesCSV(_ rows: [City]) -> String {
    var lines = [
        "city_slug,city_name,country_code,currency,published,property_count,operator_count,entry_median,entry_min,entry_max,p25,p75,sample_size,as_of",
    ]
    for row in rows {
        lines.append(
            csvLine([
                row.citySlug,
                row.cityName,
                row.countryCode,
                row.currency,
                row.published ? "true" : "false",
                row.propertyCount.map(String.init),
                row.operatorCount.map(String.init),
                row.entryMedianText,
                row.entryMinText,
                row.entryMaxText,
                row.p25Text,
                row.p75Text,
                row.sampleSize.map(String.init),
                row.asOf,
            ])
        )
    }
    return lines.joined(separator: "\n") + "\n"
}

func listingsCSV(_ rows: [Listing]) -> String {
    var lines = [
        "slug,title,city_slug,zone_slug,operator_slug,operator_name,country_code,lat,lng,featured,market_verdict,market_median,market_sample_size,url,updated_at",
    ]
    for row in rows {
        lines.append(
            csvLine([
                row.slug,
                row.title,
                row.citySlug,
                row.zoneSlug,
                row.operatorSlug,
                row.operatorName,
                row.countryCode,
                row.latText,
                row.lngText,
                row.featured.map { $0 ? "true" : "false" },
                row.marketVerdict,
                row.marketMedianText,
                row.marketSampleSize.map(String.init),
                row.url,
                row.updatedAt,
            ])
        )
    }
    return lines.joined(separator: "\n") + "\n"
}

func pricingCSV(_ rows: [PricingOption]) -> String {
    var lines = ["product,title,price,currency,billing_period,price_on_request,min_capacity,max_capacity"]
    for row in rows {
        lines.append(
            csvLine([
                row.product,
                row.title,
                row.priceText,
                row.currency,
                row.billingPeriod,
                row.priceOnRequest ? "true" : "false",
                row.minCapacity.map(String.init),
                row.maxCapacity.map(String.init),
            ])
        )
    }
    return lines.joined(separator: "\n") + "\n"
}

struct TransportFailure: Error, LocalizedError, CustomStringConvertible, Sendable {
    var message: String
    var errorDescription: String? { message }
    var description: String { message }
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Call: Sendable {
        var url: URL
        var headers: [String: String]
    }

    private var calls: [Call] = []
    var queued: [HTTPResponse] = []
    var failure: TransportFailure?
    var responder: (@Sendable (Call) -> HTTPResponse)?

    func recorded() -> [Call] {
        calls
    }

    func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        let call = Call(url: url, headers: headers)
        calls.append(call)
        if let failure {
            throw failure
        }
        if let responder {
            return responder(call)
        }
        let index = calls.count - 1
        if index < queued.count {
            return queued[index]
        }
        throw CoworkingViewError("no scripted response")
    }
}

final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private var values: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        values.append(seconds)
    }

    func recorded() -> [TimeInterval] {
        values
    }
}

func scriptedClient(
    transport: FakeTransport,
    sleeper: RecordingSleeper = RecordingSleeper(),
    baseURL: URL? = URL(string: "https://api.coworkingview.com"),
    environment: [String: String] = [:]
) throws -> Client {
    try Client(
        baseURL: baseURL,
        timeout: 20,
        userAgent: nil,
        locale: "en",
        environment: environment,
        transport: transport,
        sleeper: sleeper
    )
}

func httpResponse(
    status: Int = 200,
    body: String,
    headers: [String: String] = [:],
    reason: String? = nil
) -> HTTPResponse {
    HTTPResponse(
        status: status,
        reason: reason ?? HTTPReason.phrase(for: status),
        headers: headers,
        body: Data(body.utf8)
    )
}

func queryItems(_ url: URL) -> [String: String] {
    var items: [String: String] = [:]
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
        items[item.name] = item.value ?? ""
    }
    return items
}

func header(_ headers: [String: String], _ name: String) -> String? {
    let wanted = name.lowercased()
    return headers.first { $0.key.lowercased() == wanted }?.value
}
