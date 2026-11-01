import Foundation

struct ResponseShapeError: Error {
    var message: String
}

struct PropertyPage {
    var rows: [Listing]
    var pageCount: Int?
    var total: Int?
    var seed: String?
    var attribution: String?
    var notice: String?
}

enum Parser {
    static let productOrder = Check.products
    static let statUnits = [
        "day_pass": "day",
        "meeting_room": "hour",
        "event_space": "hour",
        "virtual_office": "month",
    ]
    static let workspacePath = ["en": "workspace", "es": "oficina", "de": "buero"]
    static let siteURL = "https://coworkingview.com"

    static func rates(envelope: JSON.Value) throws -> Dataset<[Rate]> {
        let data = try object(envelope, "data", "Unexpected shape for market rates")
        let rows = try rateRows(data)
        return Dataset(
            data: rows,
            attribution: JSONRead.string(JSONRead.field(data, "attribution")),
            license: JSONRead.string(JSONRead.field(data, "licenseUrl")),
            asOf: JSONRead.string(JSONRead.field(data, "asOf"))
        )
    }

    static func cities(envelope: JSON.Value) throws -> Dataset<[City]> {
        let data = try object(envelope, "data", "Unexpected shape for market rates")
        return Dataset(
            data: try cityRows(data),
            attribution: JSONRead.string(JSONRead.field(data, "attribution")),
            license: JSONRead.string(JSONRead.field(data, "licenseUrl")),
            asOf: JSONRead.string(JSONRead.field(data, "asOf"))
        )
    }

    static func properties(envelope: JSON.Value, locale: String) throws -> PropertyPage {
        guard let data = JSONRead.field(envelope, "data") else {
            throw ResponseShapeError(message: "The API response has no 'data' member")
        }
        guard let cards = data.array else {
            throw ResponseShapeError(message: "Unexpected shape for properties")
        }
        let meta = catalogueMeta(envelope)
        var rows: [Listing] = []
        for card in cards {
            guard card.object != nil else { continue }
            rows.append(try listing(card, locale: locale))
        }
        return PropertyPage(
            rows: rows,
            pageCount: meta.pageCount,
            total: meta.total,
            seed: meta.seed,
            attribution: meta.attribution,
            notice: meta.notice
        )
    }

    static func space(envelope: JSON.Value, locale: String) throws -> Space {
        let detail = try object(envelope, "data", "Unexpected shape for a property")
        let meta = catalogueMeta(envelope)
        return try space(detail, locale: locale, attribution: meta.attribution, notice: meta.notice)
    }

    static func snake(_ key: String) -> String {
        var result = ""
        for (offset, character) in key.enumerated() {
            if offset > 0, character.isASCII, character.isUppercase {
                result.append("_")
            }
            result.append(String(character).lowercased())
        }
        return result
    }

    private static func rateRows(_ data: JSON.Value) throws -> [Rate] {
        let asOf = JSONRead.string(JSONRead.field(data, "asOf"))
        var rows: [Rate] = []
        for city in JSONRead.field(data, "cities")?.array ?? [] {
            guard let fields = city.object else {
                throw ResponseShapeError(message: "Unexpected shape for market rates")
            }
            guard
                let slug = JSONRead.nestedString(fields["city"], "slug"),
                let name = JSONRead.nestedString(fields["city"], "name"),
                let currency = JSONRead.string(fields["currency"])
            else {
                throw ResponseShapeError(message: "Unexpected shape for market rates")
            }
            let country = JSONRead.string(fields["countryCode"])
            let series = nonEmptyArray(fields["figures"]) ?? fields["byType"]?.array ?? []
            for item in series {
                guard let option = item.object else {
                    throw ResponseShapeError(message: "Unexpected shape for market rates")
                }
                rows.append(
                    try rate(
                        citySlug: slug,
                        cityName: name,
                        countryCode: country,
                        currency: currency,
                        product: try requiredString(option, "optionType"),
                        unit: "month",
                        stat: option,
                        asOf: asOf
                    )
                )
            }
            for (key, value) in fields where isStat(value) {
                let product = snake(key)
                rows.append(
                    try rate(
                        citySlug: slug,
                        cityName: name,
                        countryCode: country,
                        currency: currency,
                        product: product,
                        unit: statUnits[product],
                        stat: value.object ?? [:],
                        asOf: asOf
                    )
                )
            }
        }
        rows.sort { lhs, rhs in
            if lhs.citySlug != rhs.citySlug { return lhs.citySlug < rhs.citySlug }
            return productKey(lhs.product) < productKey(rhs.product)
        }
        return rows
    }

    private static func cityRows(_ data: JSON.Value) throws -> [City] {
        let asOf = JSONRead.string(JSONRead.field(data, "asOf"))
        var rows: [City] = []
        for city in JSONRead.field(data, "cities")?.array ?? [] {
            guard let fields = city.object else {
                throw ResponseShapeError(message: "Unexpected shape for market rates")
            }
            guard
                let slug = JSONRead.nestedString(fields["city"], "slug"),
                let name = JSONRead.nestedString(fields["city"], "name"),
                let currency = JSONRead.string(fields["currency"])
            else {
                throw ResponseShapeError(message: "Unexpected shape for market rates")
            }
            let entryMedian = try amount(fields["entryMedian"])
            let entryMin = try amount(fields["entryMin"])
            let entryMax = try amount(fields["entryMax"])
            let p25 = try amount(fields["p25"])
            let p75 = try amount(fields["p75"])
            rows.append(
                City(
                    citySlug: slug,
                    cityName: name,
                    countryCode: JSONRead.string(fields["countryCode"]),
                    currency: currency,
                    published: true,
                    propertyCount: JSONRead.integer(fields["propertyCount"]),
                    operatorCount: JSONRead.integer(fields["operatorCount"]),
                    entryMedian: entryMedian.value,
                    entryMedianText: entryMedian.token,
                    entryMin: entryMin.value,
                    entryMinText: entryMin.token,
                    entryMax: entryMax.value,
                    entryMaxText: entryMax.token,
                    p25: p25.value,
                    p25Text: p25.token,
                    p75: p75.value,
                    p75Text: p75.token,
                    sampleSize: JSONRead.integer(fields["sampleSize"]),
                    asOf: asOf
                )
            )
        }
        for city in JSONRead.field(data, "unpublished")?.array ?? [] {
            guard let fields = city.object else {
                throw ResponseShapeError(message: "Unexpected shape for market rates")
            }
            guard
                let slug = JSONRead.nestedString(fields["city"], "slug"),
                let name = JSONRead.nestedString(fields["city"], "name")
            else {
                throw ResponseShapeError(message: "Unexpected shape for market rates")
            }
            rows.append(
                City(
                    citySlug: slug,
                    cityName: name,
                    countryCode: JSONRead.string(fields["countryCode"]),
                    currency: JSONRead.string(fields["currency"]),
                    published: false,
                    asOf: asOf
                )
            )
        }
        rows.sort { lhs, rhs in
            if lhs.published != rhs.published { return lhs.published && !rhs.published }
            return lhs.citySlug < rhs.citySlug
        }
        return rows
    }

    private static func listing(_ card: JSON.Value, locale: String) throws -> Listing {
        let parsed = try cardFields(card, locale: locale)
        return Listing(
            slug: parsed.slug,
            title: parsed.title,
            citySlug: parsed.citySlug,
            zoneSlug: parsed.zoneSlug,
            operatorSlug: parsed.operatorSlug,
            operatorName: parsed.operatorName,
            countryCode: parsed.countryCode,
            lat: parsed.lat,
            latText: parsed.latText,
            lng: parsed.lng,
            lngText: parsed.lngText,
            featured: parsed.featured,
            marketVerdict: parsed.marketVerdict,
            marketMedian: parsed.marketMedian,
            marketMedianText: parsed.marketMedianText,
            marketSampleSize: parsed.marketSampleSize,
            url: parsed.url,
            updatedAt: parsed.updatedAt
        )
    }

    private static func space(
        _ detail: JSON.Value,
        locale: String,
        attribution: String?,
        notice: String?
    ) throws -> Space {
        let parsed = try cardFields(detail, locale: locale)
        var url = parsed.url
        if let webURL = JSONRead.string(JSONRead.field(detail, "webUrl")), !webURL.isEmpty {
            url = webURL
        }
        let capacityValue = JSONRead.field(detail, "capacity")
        let capacity = JSONRead.integer(capacityValue)
        var amenities: [String] = []
        for item in JSONRead.field(detail, "amenities")?.array ?? [] {
            if let text = JSONRead.string(item) {
                amenities.append(text)
            } else if let token = JSONRead.numberToken(item) {
                amenities.append(token)
            } else if let flag = JSONRead.bool(item) {
                amenities.append(flag ? "true" : "false")
            }
        }
        var pricing: [PricingOption] = []
        for item in JSONRead.field(detail, "pricingOptions")?.array ?? [] {
            guard let option = item.object else {
                throw ResponseShapeError(message: "Unexpected shape for a property")
            }
            let price = try amount(option["price"])
            let currency = price.token == nil ? nil : JSONRead.string(option["price"]?.object?["currency"])
            guard let priceOnRequest = JSONRead.bool(option["priceOnRequest"]) else {
                throw ResponseShapeError(message: "Unexpected shape for a property")
            }
            pricing.append(
                PricingOption(
                    product: try requiredString(option, "optionType"),
                    title: try requiredString(option, "title"),
                    price: price.value,
                    priceText: price.token,
                    currency: currency,
                    billingPeriod: try requiredString(option, "billingPeriod"),
                    priceOnRequest: priceOnRequest,
                    minCapacity: JSONRead.integer(option["minCapacity"]),
                    maxCapacity: JSONRead.integer(option["maxCapacity"])
                )
            )
        }
        return Space(
            slug: parsed.slug,
            title: parsed.title,
            citySlug: parsed.citySlug,
            zoneSlug: parsed.zoneSlug,
            operatorSlug: parsed.operatorSlug,
            operatorName: parsed.operatorName,
            countryCode: parsed.countryCode,
            lat: parsed.lat,
            latText: parsed.latText,
            lng: parsed.lng,
            lngText: parsed.lngText,
            featured: parsed.featured,
            marketVerdict: parsed.marketVerdict,
            marketMedian: parsed.marketMedian,
            marketMedianText: parsed.marketMedianText,
            marketSampleSize: parsed.marketSampleSize,
            url: url,
            updatedAt: parsed.updatedAt,
            address: JSONRead.string(JSONRead.field(detail, "address")),
            capacity: capacity,
            amenities: amenities,
            pricing: pricing,
            attribution: attribution,
            notice: notice
        )
    }

    private struct Card {
        var slug: String
        var title: String
        var citySlug: String?
        var zoneSlug: String?
        var operatorSlug: String?
        var operatorName: String?
        var countryCode: String?
        var lat: Double?
        var latText: String?
        var lng: Double?
        var lngText: String?
        var featured: Bool?
        var marketVerdict: String?
        var marketMedian: Double?
        var marketMedianText: String?
        var marketSampleSize: Int?
        var url: String
        var updatedAt: String?
    }

    private static func cardFields(_ card: JSON.Value, locale: String) throws -> Card {
        guard let fields = card.object else {
            throw ResponseShapeError(message: "Unexpected shape for properties")
        }
        let slug = try requiredString(fields, "slug")
        let title = try requiredString(fields, "title")
        let market = fields["marketPosition"]?.object ?? [:]
        let median = try amount(market["median"])
        let coordinates = fields["coordinates"]
        let lat = try amountTokenOnly(JSONRead.field(coordinates, "lat"))
        let lng = try amountTokenOnly(JSONRead.field(coordinates, "lng"))
        return Card(
            slug: slug,
            title: title,
            citySlug: JSONRead.nestedString(fields["city"], "slug"),
            zoneSlug: JSONRead.nestedString(fields["zone"], "slug"),
            operatorSlug: JSONRead.nestedString(fields["operator"], "slug"),
            operatorName: JSONRead.nestedString(fields["operator"], "name"),
            countryCode: JSONRead.string(fields["countryCode"]),
            lat: lat.value,
            latText: lat.token,
            lng: lng.value,
            lngText: lng.token,
            featured: JSONRead.bool(fields["featured"]),
            marketVerdict: JSONRead.string(market["verdict"]),
            marketMedian: median.value,
            marketMedianText: median.token,
            marketSampleSize: JSONRead.integer(market["sampleSize"]),
            url: listingURL(slug: slug, locale: locale),
            updatedAt: JSONRead.string(fields["updatedAt"])
        )
    }

    static func listingURL(slug: String, locale: String) -> String {
        let section = workspacePath[locale] ?? "workspace"
        return "\(siteURL)/\(locale)/\(section)/\(slug)"
    }

    private static func catalogueMeta(_ envelope: JSON.Value) -> PropertyPage {
        let meta = JSONRead.field(envelope, "meta")?.object ?? [:]
        let citation = meta["citation"]?.object
        let pagination = meta["pagination"]?.object ?? [:]
        let seed = JSONRead.numberToken(meta["seed"]) ?? JSONRead.string(meta["seed"])
        return PropertyPage(
            rows: [],
            pageCount: JSONRead.integer(pagination["pageCount"]),
            total: JSONRead.integer(pagination["total"]),
            seed: seed,
            attribution: JSONRead.string(citation?["text"]),
            notice: JSONRead.string(meta["catalogueNotice"])
        )
    }

    private static func rate(
        citySlug: String,
        cityName: String,
        countryCode: String?,
        currency: String,
        product: String,
        unit: String?,
        stat: [String: JSON.Value],
        asOf: String?
    ) throws -> Rate {
        let median = try amount(stat["median"])
        guard let medianToken = median.token, let medianValue = median.value else {
            throw ResponseShapeError(message: "Unexpected shape for market rates")
        }
        let p25 = try amount(stat["p25"])
        let p75 = try amount(stat["p75"])
        guard let sampleSize = JSONRead.integer(stat["sampleSize"]) else {
            throw ResponseShapeError(message: "Unexpected shape for market rates")
        }
        return Rate(
            citySlug: citySlug,
            cityName: cityName,
            countryCode: countryCode,
            currency: currency,
            product: product,
            unit: unit,
            median: medianValue,
            medianText: medianToken,
            p25: p25.value,
            p25Text: p25.token,
            p75: p75.value,
            p75Text: p75.token,
            sampleSize: sampleSize,
            propertyCount: JSONRead.integer(stat["propertyCount"]),
            operatorCount: JSONRead.integer(stat["operatorCount"]),
            asOf: asOf
        )
    }

    private static func isStat(_ value: JSON.Value) -> Bool {
        guard let fields = value.object else { return false }
        return fields["median"] != nil && fields["sampleSize"] != nil
    }

    private static func nonEmptyArray(_ value: JSON.Value?) -> [JSON.Value]? {
        guard let items = value?.array, !items.isEmpty else { return nil }
        return items
    }

    private static func object(_ envelope: JSON.Value, _ key: String, _ message: String) throws -> JSON.Value {
        guard let value = JSONRead.field(envelope, key) else {
            throw ResponseShapeError(message: "The API response has no '\(key)' member")
        }
        guard value.object != nil else { throw ResponseShapeError(message: message) }
        return value
    }

    private static func requiredString(_ fields: [String: JSON.Value], _ key: String) throws -> String {
        guard let text = JSONRead.string(fields[key]) else {
            throw ResponseShapeError(message: "Unexpected shape for a property")
        }
        return text
    }

    private struct Money {
        var token: String?
        var value: Double?
    }

    private static func amount(_ value: JSON.Value?) throws -> Money {
        guard let value, !value.isNull else { return Money(token: nil, value: nil) }
        guard let token = JSONRead.numberToken(value.object?["amount"]) else {
            throw ResponseShapeError(message: "Unexpected shape for a price")
        }
        guard let number = JSONRead.double(token: token) else {
            throw ResponseShapeError(message: "Unexpected shape for a price")
        }
        return Money(token: token, value: number)
    }

    private static func amountTokenOnly(_ value: JSON.Value?) throws -> Money {
        guard let value, !value.isNull else { return Money(token: nil, value: nil) }
        guard let token = JSONRead.numberToken(value) else {
            throw ResponseShapeError(message: "Unexpected shape for a price")
        }
        guard let number = JSONRead.double(token: token) else {
            throw ResponseShapeError(message: "Unexpected shape for a price")
        }
        return Money(token: token, value: number)
    }

    private static func productKey(_ product: String) -> (Int, String) {
        if let index = productOrder.firstIndex(of: product) {
            return (index, "")
        }
        return (productOrder.count, product)
    }
}
