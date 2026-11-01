import Foundation

enum NumberText {
    static func from(_ value: Double) -> String {
        Check.decimal(value)
    }

    static func from(optional value: Double?) -> String? {
        value.map(from)
    }
}

/// A result plus the credit that has to travel with it.
///
/// Price Index calls set ``attribution``, ``license`` and ``asOf``.
/// Catalogue calls set ``attribution`` (the citation), ``notice`` and, for a
/// search, ``total``.
public struct Dataset<Value: Codable & Equatable & Hashable & Sendable>: Codable, Equatable, Hashable, Sendable {
    /// The rows or the space.
    public let data: Value

    /// Text to show next to anything you republish. From CoworkingView.
    public let attribution: String?

    /// Licence URL for Price Index figures (`licenseUrl` on the response).
    public let license: String?

    /// When the index was computed (`asOf`), as the API wrote it.
    public let asOf: String?

    /// Catalogue notice. Descriptions, photos and logos are not included.
    public let notice: String?

    /// `pagination.total` from the first page of a search.
    public let total: Int?

    public init(
        data: Value,
        attribution: String? = nil,
        license: String? = nil,
        asOf: String? = nil,
        notice: String? = nil,
        total: Int? = nil
    ) {
        self.data = data
        self.attribution = attribution
        self.license = license
        self.asOf = asOf
        self.notice = notice
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case attribution
        case license
        case asOf = "as_of"
        case notice
        case total
    }
}

/// One Price Index figure: a published city and a product.
public struct Rate: Codable, Equatable, Hashable, Sendable {
    public let citySlug: String
    public let cityName: String
    public let countryCode: String?
    public let currency: String
    /// Product code, for example `flex_desk`. Unknown products pass through.
    public let product: String
    /// `month`, `day`, `hour`, or `nil` for an aggregate this version does not name.
    public let unit: String?
    public let median: Double
    /// Exact `median` token from the API (`214`, not `214.0`).
    public let medianText: String
    public let p25: Double?
    public let p25Text: String?
    public let p75: Double?
    public let p75Text: String?
    public let sampleSize: Int
    public let propertyCount: Int?
    public let operatorCount: Int?
    /// `true` when ``sampleSize`` is below 10.
    public let lowConfidence: Bool
    public let asOf: String?

    public init(
        citySlug: String,
        cityName: String,
        countryCode: String?,
        currency: String,
        product: String,
        unit: String?,
        median: Double,
        medianText: String? = nil,
        p25: Double? = nil,
        p25Text: String? = nil,
        p75: Double? = nil,
        p75Text: String? = nil,
        sampleSize: Int,
        propertyCount: Int? = nil,
        operatorCount: Int? = nil,
        lowConfidence: Bool? = nil,
        asOf: String? = nil
    ) {
        self.citySlug = citySlug
        self.cityName = cityName
        self.countryCode = countryCode
        self.currency = currency
        self.product = product
        self.unit = unit
        self.median = median
        self.medianText = medianText ?? NumberText.from(median)
        self.p25 = p25
        self.p25Text = p25 == nil ? nil : (p25Text ?? NumberText.from(optional: p25))
        self.p75 = p75
        self.p75Text = p75 == nil ? nil : (p75Text ?? NumberText.from(optional: p75))
        self.sampleSize = sampleSize
        self.propertyCount = propertyCount
        self.operatorCount = operatorCount
        self.lowConfidence = lowConfidence ?? (sampleSize < 10)
        self.asOf = asOf
    }

    private enum CodingKeys: String, CodingKey {
        case citySlug = "city_slug"
        case cityName = "city_name"
        case countryCode = "country_code"
        case currency
        case product
        case unit
        case median
        case p25
        case p75
        case sampleSize = "sample_size"
        case propertyCount = "property_count"
        case operatorCount = "operator_count"
        case lowConfidence = "low_confidence"
        case asOf = "as_of"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let median = try container.decode(Double.self, forKey: .median)
        let p25 = try container.decodeIfPresent(Double.self, forKey: .p25)
        let p75 = try container.decodeIfPresent(Double.self, forKey: .p75)
        let sampleSize = try container.decode(Int.self, forKey: .sampleSize)
        self.init(
            citySlug: try container.decode(String.self, forKey: .citySlug),
            cityName: try container.decode(String.self, forKey: .cityName),
            countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
            currency: try container.decode(String.self, forKey: .currency),
            product: try container.decode(String.self, forKey: .product),
            unit: try container.decodeIfPresent(String.self, forKey: .unit),
            median: median,
            p25: p25,
            p75: p75,
            sampleSize: sampleSize,
            propertyCount: try container.decodeIfPresent(Int.self, forKey: .propertyCount),
            operatorCount: try container.decodeIfPresent(Int.self, forKey: .operatorCount),
            lowConfidence: try container.decodeIfPresent(Bool.self, forKey: .lowConfidence),
            asOf: try container.decodeIfPresent(String.self, forKey: .asOf)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(citySlug, forKey: .citySlug)
        try container.encode(cityName, forKey: .cityName)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(currency, forKey: .currency)
        try container.encode(product, forKey: .product)
        try container.encode(unit, forKey: .unit)
        try container.encode(median, forKey: .median)
        try container.encode(p25, forKey: .p25)
        try container.encode(p75, forKey: .p75)
        try container.encode(sampleSize, forKey: .sampleSize)
        try container.encode(propertyCount, forKey: .propertyCount)
        try container.encode(operatorCount, forKey: .operatorCount)
        try container.encode(lowConfidence, forKey: .lowConfidence)
        try container.encode(asOf, forKey: .asOf)
    }
}

/// One city covered by the Price Index.
public struct City: Codable, Equatable, Hashable, Sendable {
    public let citySlug: String
    public let cityName: String
    public let countryCode: String?
    public let currency: String?
    /// `true` for cities in `cities`, `false` for `unpublished`.
    public let published: Bool
    public let propertyCount: Int?
    public let operatorCount: Int?
    public let entryMedian: Double?
    public let entryMedianText: String?
    public let entryMin: Double?
    public let entryMinText: String?
    public let entryMax: Double?
    public let entryMaxText: String?
    public let p25: Double?
    public let p25Text: String?
    public let p75: Double?
    public let p75Text: String?
    public let sampleSize: Int?
    public let asOf: String?

    public init(
        citySlug: String,
        cityName: String,
        countryCode: String?,
        currency: String?,
        published: Bool,
        propertyCount: Int? = nil,
        operatorCount: Int? = nil,
        entryMedian: Double? = nil,
        entryMedianText: String? = nil,
        entryMin: Double? = nil,
        entryMinText: String? = nil,
        entryMax: Double? = nil,
        entryMaxText: String? = nil,
        p25: Double? = nil,
        p25Text: String? = nil,
        p75: Double? = nil,
        p75Text: String? = nil,
        sampleSize: Int? = nil,
        asOf: String? = nil
    ) {
        self.citySlug = citySlug
        self.cityName = cityName
        self.countryCode = countryCode
        self.currency = currency
        self.published = published
        self.propertyCount = propertyCount
        self.operatorCount = operatorCount
        self.entryMedian = entryMedian
        self.entryMedianText = text(entryMedian, entryMedianText)
        self.entryMin = entryMin
        self.entryMinText = text(entryMin, entryMinText)
        self.entryMax = entryMax
        self.entryMaxText = text(entryMax, entryMaxText)
        self.p25 = p25
        self.p25Text = text(p25, p25Text)
        self.p75 = p75
        self.p75Text = text(p75, p75Text)
        self.sampleSize = sampleSize
        self.asOf = asOf
    }

    private enum CodingKeys: String, CodingKey {
        case citySlug = "city_slug"
        case cityName = "city_name"
        case countryCode = "country_code"
        case currency
        case published
        case propertyCount = "property_count"
        case operatorCount = "operator_count"
        case entryMedian = "entry_median"
        case entryMin = "entry_min"
        case entryMax = "entry_max"
        case p25
        case p75
        case sampleSize = "sample_size"
        case asOf = "as_of"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            citySlug: try container.decode(String.self, forKey: .citySlug),
            cityName: try container.decode(String.self, forKey: .cityName),
            countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
            currency: try container.decodeIfPresent(String.self, forKey: .currency),
            published: try container.decode(Bool.self, forKey: .published),
            propertyCount: try container.decodeIfPresent(Int.self, forKey: .propertyCount),
            operatorCount: try container.decodeIfPresent(Int.self, forKey: .operatorCount),
            entryMedian: try container.decodeIfPresent(Double.self, forKey: .entryMedian),
            entryMin: try container.decodeIfPresent(Double.self, forKey: .entryMin),
            entryMax: try container.decodeIfPresent(Double.self, forKey: .entryMax),
            p25: try container.decodeIfPresent(Double.self, forKey: .p25),
            p75: try container.decodeIfPresent(Double.self, forKey: .p75),
            sampleSize: try container.decodeIfPresent(Int.self, forKey: .sampleSize),
            asOf: try container.decodeIfPresent(String.self, forKey: .asOf)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(citySlug, forKey: .citySlug)
        try container.encode(cityName, forKey: .cityName)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(currency, forKey: .currency)
        try container.encode(published, forKey: .published)
        try container.encode(propertyCount, forKey: .propertyCount)
        try container.encode(operatorCount, forKey: .operatorCount)
        try container.encode(entryMedian, forKey: .entryMedian)
        try container.encode(entryMin, forKey: .entryMin)
        try container.encode(entryMax, forKey: .entryMax)
        try container.encode(p25, forKey: .p25)
        try container.encode(p75, forKey: .p75)
        try container.encode(sampleSize, forKey: .sampleSize)
        try container.encode(asOf, forKey: .asOf)
    }
}

/// One catalogue row from ``Client/spaces(city:country:zone:operator:product:minCapacity:minPrice:maxPrice:currency:sort:limit:locale:seed:)``.
public struct Listing: Codable, Equatable, Hashable, Sendable {
    public let slug: String
    public let title: String
    public let citySlug: String?
    public let zoneSlug: String?
    public let operatorSlug: String?
    public let operatorName: String?
    public let countryCode: String?
    public let lat: Double?
    public let latText: String?
    public let lng: Double?
    public let lngText: String?
    public let featured: Bool?
    /// `below`, `around` or `above`, when the API sent a market position.
    public let marketVerdict: String?
    public let marketMedian: Double?
    public let marketMedianText: String?
    public let marketSampleSize: Int?
    /// Listing page on coworkingview.com.
    public let url: String
    public let updatedAt: String?

    public init(
        slug: String,
        title: String,
        citySlug: String? = nil,
        zoneSlug: String? = nil,
        operatorSlug: String? = nil,
        operatorName: String? = nil,
        countryCode: String? = nil,
        lat: Double? = nil,
        latText: String? = nil,
        lng: Double? = nil,
        lngText: String? = nil,
        featured: Bool? = nil,
        marketVerdict: String? = nil,
        marketMedian: Double? = nil,
        marketMedianText: String? = nil,
        marketSampleSize: Int? = nil,
        url: String,
        updatedAt: String? = nil
    ) {
        self.slug = slug
        self.title = title
        self.citySlug = citySlug
        self.zoneSlug = zoneSlug
        self.operatorSlug = operatorSlug
        self.operatorName = operatorName
        self.countryCode = countryCode
        self.lat = lat
        self.latText = text(lat, latText)
        self.lng = lng
        self.lngText = text(lng, lngText)
        self.featured = featured
        self.marketVerdict = marketVerdict
        self.marketMedian = marketMedian
        self.marketMedianText = text(marketMedian, marketMedianText)
        self.marketSampleSize = marketSampleSize
        self.url = url
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case title
        case citySlug = "city_slug"
        case zoneSlug = "zone_slug"
        case operatorSlug = "operator_slug"
        case operatorName = "operator_name"
        case countryCode = "country_code"
        case lat
        case lng
        case featured
        case marketVerdict = "market_verdict"
        case marketMedian = "market_median"
        case marketSampleSize = "market_sample_size"
        case url
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            slug: try container.decode(String.self, forKey: .slug),
            title: try container.decode(String.self, forKey: .title),
            citySlug: try container.decodeIfPresent(String.self, forKey: .citySlug),
            zoneSlug: try container.decodeIfPresent(String.self, forKey: .zoneSlug),
            operatorSlug: try container.decodeIfPresent(String.self, forKey: .operatorSlug),
            operatorName: try container.decodeIfPresent(String.self, forKey: .operatorName),
            countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
            lat: try container.decodeIfPresent(Double.self, forKey: .lat),
            lng: try container.decodeIfPresent(Double.self, forKey: .lng),
            featured: try container.decodeIfPresent(Bool.self, forKey: .featured),
            marketVerdict: try container.decodeIfPresent(String.self, forKey: .marketVerdict),
            marketMedian: try container.decodeIfPresent(Double.self, forKey: .marketMedian),
            marketSampleSize: try container.decodeIfPresent(Int.self, forKey: .marketSampleSize),
            url: try container.decode(String.self, forKey: .url),
            updatedAt: try container.decodeIfPresent(String.self, forKey: .updatedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(title, forKey: .title)
        try container.encode(citySlug, forKey: .citySlug)
        try container.encode(zoneSlug, forKey: .zoneSlug)
        try container.encode(operatorSlug, forKey: .operatorSlug)
        try container.encode(operatorName, forKey: .operatorName)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encode(featured, forKey: .featured)
        try container.encode(marketVerdict, forKey: .marketVerdict)
        try container.encode(marketMedian, forKey: .marketMedian)
        try container.encode(marketSampleSize, forKey: .marketSampleSize)
        try container.encode(url, forKey: .url)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// One price option on a space. `price` is `nil` when the operator quotes on request.
public struct PricingOption: Codable, Equatable, Hashable, Sendable {
    public let product: String
    public let title: String
    public let price: Double?
    public let priceText: String?
    public let currency: String?
    public let billingPeriod: String
    public let priceOnRequest: Bool
    public let minCapacity: Int?
    public let maxCapacity: Int?

    public init(
        product: String,
        title: String,
        price: Double? = nil,
        priceText: String? = nil,
        currency: String? = nil,
        billingPeriod: String,
        priceOnRequest: Bool,
        minCapacity: Int? = nil,
        maxCapacity: Int? = nil
    ) {
        self.product = product
        self.title = title
        self.price = price
        self.priceText = text(price, priceText)
        self.currency = currency
        self.billingPeriod = billingPeriod
        self.priceOnRequest = priceOnRequest
        self.minCapacity = minCapacity
        self.maxCapacity = maxCapacity
    }

    private enum CodingKeys: String, CodingKey {
        case product
        case title
        case price
        case currency
        case billingPeriod = "billing_period"
        case priceOnRequest = "price_on_request"
        case minCapacity = "min_capacity"
        case maxCapacity = "max_capacity"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            product: try container.decode(String.self, forKey: .product),
            title: try container.decode(String.self, forKey: .title),
            price: try container.decodeIfPresent(Double.self, forKey: .price),
            currency: try container.decodeIfPresent(String.self, forKey: .currency),
            billingPeriod: try container.decode(String.self, forKey: .billingPeriod),
            priceOnRequest: try container.decode(Bool.self, forKey: .priceOnRequest),
            minCapacity: try container.decodeIfPresent(Int.self, forKey: .minCapacity),
            maxCapacity: try container.decodeIfPresent(Int.self, forKey: .maxCapacity)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(product, forKey: .product)
        try container.encode(title, forKey: .title)
        try container.encode(price, forKey: .price)
        try container.encode(currency, forKey: .currency)
        try container.encode(billingPeriod, forKey: .billingPeriod)
        try container.encode(priceOnRequest, forKey: .priceOnRequest)
        try container.encode(minCapacity, forKey: .minCapacity)
        try container.encode(maxCapacity, forKey: .maxCapacity)
    }
}

/// One space and its pricing table. Descriptions, photos and logos are not included.
public struct Space: Codable, Equatable, Hashable, Sendable {
    public let slug: String
    public let title: String
    public let citySlug: String?
    public let zoneSlug: String?
    public let operatorSlug: String?
    public let operatorName: String?
    public let countryCode: String?
    public let lat: Double?
    public let latText: String?
    public let lng: Double?
    public let lngText: String?
    public let featured: Bool?
    public let marketVerdict: String?
    public let marketMedian: Double?
    public let marketMedianText: String?
    public let marketSampleSize: Int?
    /// `webUrl` when the API sent one, otherwise the listing page for ``Client/space(slug:locale:)``'s locale.
    public let url: String
    public let updatedAt: String?
    public let address: String?
    /// Integer `capacity` from the detail, when the operator published one.
    public let capacity: Int?
    public let amenities: [String]
    public let pricing: [PricingOption]
    public let attribution: String?
    public let notice: String?

    public init(
        slug: String,
        title: String,
        citySlug: String? = nil,
        zoneSlug: String? = nil,
        operatorSlug: String? = nil,
        operatorName: String? = nil,
        countryCode: String? = nil,
        lat: Double? = nil,
        latText: String? = nil,
        lng: Double? = nil,
        lngText: String? = nil,
        featured: Bool? = nil,
        marketVerdict: String? = nil,
        marketMedian: Double? = nil,
        marketMedianText: String? = nil,
        marketSampleSize: Int? = nil,
        url: String,
        updatedAt: String? = nil,
        address: String? = nil,
        capacity: Int? = nil,
        amenities: [String] = [],
        pricing: [PricingOption] = [],
        attribution: String? = nil,
        notice: String? = nil
    ) {
        self.slug = slug
        self.title = title
        self.citySlug = citySlug
        self.zoneSlug = zoneSlug
        self.operatorSlug = operatorSlug
        self.operatorName = operatorName
        self.countryCode = countryCode
        self.lat = lat
        self.latText = text(lat, latText)
        self.lng = lng
        self.lngText = text(lng, lngText)
        self.featured = featured
        self.marketVerdict = marketVerdict
        self.marketMedian = marketMedian
        self.marketMedianText = text(marketMedian, marketMedianText)
        self.marketSampleSize = marketSampleSize
        self.url = url
        self.updatedAt = updatedAt
        self.address = address
        self.capacity = capacity
        self.amenities = amenities
        self.pricing = pricing
        self.attribution = attribution
        self.notice = notice
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case title
        case citySlug = "city_slug"
        case zoneSlug = "zone_slug"
        case operatorSlug = "operator_slug"
        case operatorName = "operator_name"
        case countryCode = "country_code"
        case lat
        case lng
        case featured
        case marketVerdict = "market_verdict"
        case marketMedian = "market_median"
        case marketSampleSize = "market_sample_size"
        case url
        case updatedAt = "updated_at"
        case address
        case capacity
        case amenities
        case pricing
        case attribution
        case notice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            slug: try container.decode(String.self, forKey: .slug),
            title: try container.decode(String.self, forKey: .title),
            citySlug: try container.decodeIfPresent(String.self, forKey: .citySlug),
            zoneSlug: try container.decodeIfPresent(String.self, forKey: .zoneSlug),
            operatorSlug: try container.decodeIfPresent(String.self, forKey: .operatorSlug),
            operatorName: try container.decodeIfPresent(String.self, forKey: .operatorName),
            countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
            lat: try container.decodeIfPresent(Double.self, forKey: .lat),
            lng: try container.decodeIfPresent(Double.self, forKey: .lng),
            featured: try container.decodeIfPresent(Bool.self, forKey: .featured),
            marketVerdict: try container.decodeIfPresent(String.self, forKey: .marketVerdict),
            marketMedian: try container.decodeIfPresent(Double.self, forKey: .marketMedian),
            marketSampleSize: try container.decodeIfPresent(Int.self, forKey: .marketSampleSize),
            url: try container.decode(String.self, forKey: .url),
            updatedAt: try container.decodeIfPresent(String.self, forKey: .updatedAt),
            address: try container.decodeIfPresent(String.self, forKey: .address),
            capacity: try container.decodeIfPresent(Int.self, forKey: .capacity),
            amenities: try container.decodeIfPresent([String].self, forKey: .amenities) ?? [],
            pricing: try container.decodeIfPresent([PricingOption].self, forKey: .pricing) ?? [],
            attribution: try container.decodeIfPresent(String.self, forKey: .attribution),
            notice: try container.decodeIfPresent(String.self, forKey: .notice)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(title, forKey: .title)
        try container.encode(citySlug, forKey: .citySlug)
        try container.encode(zoneSlug, forKey: .zoneSlug)
        try container.encode(operatorSlug, forKey: .operatorSlug)
        try container.encode(operatorName, forKey: .operatorName)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encode(featured, forKey: .featured)
        try container.encode(marketVerdict, forKey: .marketVerdict)
        try container.encode(marketMedian, forKey: .marketMedian)
        try container.encode(marketSampleSize, forKey: .marketSampleSize)
        try container.encode(url, forKey: .url)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(address, forKey: .address)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(amenities, forKey: .amenities)
        try container.encode(pricing, forKey: .pricing)
        try container.encode(attribution, forKey: .attribution)
        try container.encode(notice, forKey: .notice)
    }
}

private func text(_ value: Double?, _ token: String?) -> String? {
    guard value != nil else { return nil }
    return token ?? NumberText.from(optional: value)
}
