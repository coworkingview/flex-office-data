import Foundation

/// Client for the public [CoworkingView](https://coworkingview.com) API.
///
/// The API needs no key. Creating a client does not touch the network. On HTTP
/// 429 or 5xx the client waits `Retry-After` seconds, else `RateLimit-Reset`,
/// else 2 seconds, and never more than 10 seconds, then retries once.
///
/// ```swift
/// let client = try Client()
/// let berlin = try await client.rates(city: "berlin")
/// print(berlin.attribution ?? "")
/// ```
///
/// Price Index figures are CC BY 4.0. Keep ``Dataset/attribution`` next to
/// anything you republish. Catalogue names and prices are for search and
/// reference. Descriptions, photos and logos are not returned.
public final class Client: @unchecked Sendable {
    /// Production API root.
    public static let defaultBaseURL = URL(string: "https://api.coworkingview.com")!

    /// Environment variable that overrides ``defaultBaseURL``.
    public static let baseURLEnvironment = "COWORKINGVIEW_API_URL"

    /// Version sent in the default `User-Agent`.
    public static let version = "0.1.0"

    /// Most rows ``spaces(city:country:zone:operator:product:minCapacity:minPrice:maxPrice:currency:sort:limit:locale:seed:)`` will return.
    public static let maxSpaces = Check.maxSpaces

    /// Default `User-Agent`.
    public static let defaultUserAgent =
        "coworkingview-swift/\(version) (+https://github.com/coworkingview/flex-office-data)"

    /// API root, without a trailing slash.
    public let baseURL: URL

    /// Per-request timeout in seconds.
    public let timeout: TimeInterval

    /// `User-Agent` sent with every request.
    public let userAgent: String

    /// Locale used when a call does not set one. `en`, `es` or `de`.
    public let locale: String

    private let transport: any HTTPTransport
    private let sleeper: any Sleeper

    /// A client for ``defaultBaseURL``, or for `COWORKINGVIEW_API_URL` when that
    /// variable is set.
    ///
    /// - Parameters:
    ///   - baseURL: API root. A trailing slash is removed. Pass `nil` to use the
    ///     environment variable, then ``defaultBaseURL``.
    ///   - timeout: Seconds to wait for each response. The default is 20.
    ///   - userAgent: `User-Agent` header. The default names this library.
    ///     Append your own product token if you build on top of the client.
    ///   - locale: Default locale for calls that do not set one.
    public convenience init(
        baseURL: URL? = nil,
        timeout: TimeInterval = 20,
        userAgent: String? = nil,
        locale: String = "en"
    ) throws {
        try self.init(
            baseURL: baseURL,
            timeout: timeout,
            userAgent: userAgent,
            locale: locale,
            environment: ProcessInfo.processInfo.environment,
            transport: nil,
            sleeper: TaskSleeper()
        )
    }

    init(
        baseURL: URL?,
        timeout: TimeInterval,
        userAgent: String?,
        locale: String,
        environment: [String: String],
        transport: (any HTTPTransport)?,
        sleeper: any Sleeper
    ) throws {
        let resolvedTimeout = try Check.timeout(timeout)
        let resolvedLocale = try Check.locale(locale)
        let resolvedURL = try Self.resolveBaseURL(baseURL, environment: environment)
        let agent = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.baseURL = resolvedURL
        self.timeout = resolvedTimeout
        self.userAgent = agent.isEmpty ? Self.defaultUserAgent : agent
        self.locale = resolvedLocale
        self.transport = transport ?? URLSessionTransport(timeout: resolvedTimeout)
        self.sleeper = sleeper
    }

    /// Price Index figures, one row per published city and product.
    ///
    /// `GET /v1/market/rates`. Rows are ordered by city slug, then by product.
    /// Cities in `unpublished` produce no rows. A product the API adds later
    /// is kept, so a new aggregate does not need a new release.
    ///
    /// - Parameters:
    ///   - city: City slug, for example `berlin`.
    ///   - country: Country code, for example `DE`.
    ///   - currency: `EUR`, `GBP`, `USD`, `CHF`, `AED` or `VES`. Any case.
    ///     `nil` keeps each city's own currency. `VES` is sent through; the API
    ///     answers 400 where it has no conversion rate.
    ///   - locale: `en`, `es` or `de`. `nil` uses the client's locale.
    /// - Returns: The figures, with attribution from CoworkingView.
    public func rates(
        city: String? = nil,
        country: String? = nil,
        currency: String? = nil,
        locale: String? = nil
    ) async throws -> Dataset<[Rate]> {
        let query = try ratesQuery(city: city, country: country, currency: currency, locale: locale)
        let response = try await get("/v1/market/rates", query: query)
        do {
            return try Parser.rates(envelope: response.value)
        } catch let error as ResponseShapeError {
            throw HTTPBody.shape(error, status: response.status, path: "/v1/market/rates")
        }
    }

    /// Cities of the Price Index, published cities first.
    ///
    /// Same request as ``rates(city:country:currency:locale:)``.
    public func cities(
        city: String? = nil,
        country: String? = nil,
        currency: String? = nil,
        locale: String? = nil
    ) async throws -> Dataset<[City]> {
        let query = try ratesQuery(city: city, country: country, currency: currency, locale: locale)
        let response = try await get("/v1/market/rates", query: query)
        do {
            return try Parser.cities(envelope: response.value)
        } catch let error as ResponseShapeError {
            throw HTTPBody.shape(error, status: response.status, path: "/v1/market/rates")
        }
    }

    /// Searches the catalogue. One row per space, at most ``maxSpaces``.
    ///
    /// `GET /v1/properties`. Pages are followed until `limit` rows or the last
    /// page. Page size is `min(50, limit)`. With `sort` `random`, the seed of
    /// the first page is sent again on the following pages.
    ///
    /// - Parameters:
    ///   - city: City slug.
    ///   - country: Country code.
    ///   - zone: Neighbourhood slug.
    ///   - operator: Operator slug. The argument is the API's `operator`.
    ///   - product: Pricing option type, sent as `pricingOptionType`.
    ///   - minCapacity: Minimum capacity. Sent as `minCapacity`.
    ///   - minPrice: Minimum price. Sent as `minPrice`.
    ///   - maxPrice: Maximum price. Sent as `maxPrice`.
    ///   - currency: Currency code.
    ///   - sort: `random` (default), `price-asc`, `date-desc` or `date-asc`. Sent as `sortBy`.
    ///   - limit: Rows to return, from 1 to 200. The default is 50.
    ///   - locale: `en`, `es` or `de`.
    ///   - seed: Random seed. When `nil` and `sort` is `random`, the first response's `meta.seed` is reused.
    public func spaces(
        city: String? = nil,
        country: String? = nil,
        zone: String? = nil,
        `operator`: String? = nil,
        product: String? = nil,
        minCapacity: Int? = nil,
        minPrice: Double? = nil,
        maxPrice: Double? = nil,
        currency: String? = nil,
        sort: String = "random",
        limit: Int = 50,
        locale: String? = nil,
        seed: String? = nil
    ) async throws -> Dataset<[Listing]> {
        let requestLocale = try Check.locale(locale ?? self.locale)
        let requestSort = try Check.sort(sort)
        let requestLimit = try Check.limit(limit)
        let low = try Check.price("min_price", minPrice)
        let high = try Check.price("max_price", maxPrice)
        try Check.priceRange(minPrice: low, maxPrice: high)
        let pageSize = min(50, requestLimit)
        var query: [(String, String)] = []
        append(&query, "locale", requestLocale)
        append(&query, "city", try Check.text("city", city))
        append(&query, "country", try Check.text("country", country))
        append(&query, "zone", try Check.text("zone", zone))
        append(&query, "operator", try Check.text("operator", `operator`))
        append(&query, "pricingOptionType", try Check.product(product))
        if let capacity = try Check.count("min_capacity", minCapacity) {
            append(&query, "minCapacity", String(capacity))
        }
        append(&query, "minPrice", low.map(Check.decimal))
        append(&query, "maxPrice", high.map(Check.decimal))
        append(&query, "currency", try Check.currency(currency))
        append(&query, "sortBy", requestSort)
        let userSeed = seed?.trimmingCharacters(in: .whitespacesAndNewlines)
        var activeSeed = (userSeed?.isEmpty == false) ? userSeed : nil
        var rows: [Listing] = []
        var first: PropertyPage?
        var page = 1
        let path = "/v1/properties"
        while true {
            var pageQuery = query
            append(&pageQuery, "page", String(page))
            append(&pageQuery, "pageSize", String(pageSize))
            append(&pageQuery, "seed", activeSeed)
            let response = try await get(path, query: pageQuery)
            let parsed: PropertyPage
            do {
                parsed = try Parser.properties(envelope: response.value, locale: requestLocale)
            } catch let error as ResponseShapeError {
                throw HTTPBody.shape(error, status: response.status, path: path)
            }
            if page == 1 {
                first = parsed
                if requestSort == "random", userSeed == nil || userSeed?.isEmpty != false, let responseSeed = parsed.seed {
                    activeSeed = responseSeed
                }
            }
            rows.append(contentsOf: parsed.rows)
            let last = parsed.pageCount == nil || page >= parsed.pageCount!
            if rows.count >= requestLimit || parsed.rows.isEmpty || last {
                break
            }
            page += 1
        }
        let kept = Array(rows.prefix(requestLimit))
        return Dataset(
            data: kept,
            attribution: first?.attribution,
            notice: first?.notice,
            total: first?.total
        )
    }

    /// One space and its pricing table.
    ///
    /// `GET /v1/properties/{slug}`. The slug is checked before it is put in the path.
    ///
    /// - Parameters:
    ///   - slug: Space slug from a search.
    ///   - locale: `en`, `es` or `de`. Used for the request and, when the
    ///     response has no `webUrl`, for the listing link.
    public func space(slug: String, locale: String? = nil) async throws -> Dataset<Space> {
        let requestLocale = try Check.locale(locale ?? self.locale)
        let checked = try Check.slug(slug)
        let path = "/v1/properties/\(checked)"
        let response = try await get(path, query: [("locale", requestLocale)])
        do {
            let parsed = try Parser.space(envelope: response.value, locale: requestLocale)
            return Dataset(data: parsed, attribution: parsed.attribution, notice: parsed.notice)
        } catch let error as ResponseShapeError {
            throw HTTPBody.shape(error, status: response.status, path: path)
        }
    }

    private struct Success {
        var status: Int
        var value: JSON.Value
    }

    private func ratesQuery(
        city: String?,
        country: String?,
        currency: String?,
        locale: String?
    ) throws -> [(String, String)] {
        var query: [(String, String)] = []
        append(&query, "locale", try Check.locale(locale ?? self.locale))
        append(&query, "city", try Check.text("city", city))
        append(&query, "country", try Check.text("country", country))
        append(&query, "currency", try Check.currency(currency))
        return query
    }

    private func get(_ path: String, query: [(String, String)]) async throws -> Success {
        let url = try makeURL(path: path, query: query)
        let headers = ["Accept": "application/json", "User-Agent": userAgent]
        var attempt = 0
        while true {
            attempt += 1
            let response: HTTPResponse
            do {
                response = try await transport.get(url: url, headers: headers, timeout: timeout)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CoworkingViewError {
                throw error
            } catch {
                throw CoworkingViewError("Could not reach \(baseURL.absoluteString): \(error.localizedDescription)")
            }
            if (200..<300).contains(response.status) {
                return Success(status: response.status, value: try HTTPBody.envelope(response: response, path: path))
            }
            if attempt == 1, HTTPBody.isRetryable(response.status) {
                try await sleeper.sleep(seconds: RetryDelay.seconds(headers: response.headers))
                continue
            }
            throw HTTPBody.problem(response)
        }
    }

    private func makeURL(path: String, query: [(String, String)]) throws -> URL {
        guard var components = URLComponents(string: baseURL.absoluteString + path) else {
            throw CoworkingViewError("Could not build URL for \(path).")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw CoworkingViewError("Could not build URL for \(path).")
        }
        return url
    }

    private func append(_ query: inout [(String, String)], _ name: String, _ value: String?) {
        if let value {
            query.append((name, value))
        }
    }

    private static func resolveBaseURL(_ baseURL: URL?, environment: [String: String]) throws -> URL {
        let fromEnv = environment[baseURLEnvironment]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var resolved: String
        if let baseURL {
            resolved = baseURL.absoluteString
        } else if !fromEnv.isEmpty {
            resolved = fromEnv
        } else {
            resolved = defaultBaseURL.absoluteString
        }
        while resolved.hasSuffix("/") {
            resolved.removeLast()
        }
        guard
            let url = URL(string: resolved),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw CoworkingViewError("base URL is not a valid http(s) URL, got '\(resolved)'.")
        }
        return url
    }
}

extension Client: CustomStringConvertible {
    public var description: String {
        "Client(baseURL: \(baseURL.absoluteString), timeout: \(timeout))"
    }
}
