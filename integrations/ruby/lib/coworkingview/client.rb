# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

require_relative "version"

module CoworkingView
  # Failure before an HTTP response arrived (DNS, connection refused, timeout).
  class Error < StandardError
    attr_reader :status, :code

    def initialize(message, status: 0, code: "CONNECTION")
      @status = status
      @code = code
      super(message)
    end
  end

  # The API answered with an error, or with a body that is not usable JSON.
  #
  # +status+ is the HTTP status, never the status copied out of a problem body.
  # +code+ is the problem document's +code+, or +HTTP_<status>+ / +BAD_RESPONSE+.
  class APIError < Error
    attr_reader :title, :detail, :errors

    def initialize(status:, code:, title:, detail: nil, errors: nil)
      @title = title
      @detail = detail
      @errors = errors.is_a?(Array) ? errors.select { |item| item.is_a?(Hash) } : []
      message = "#{status} #{code}: #{title}"
      message = "#{message} (#{detail})" if detail
      super(message, status: status, code: code)
    end
  end

  # Rows from one call, plus the attribution that has to travel with them.
  class Dataset
    attr_reader :data, :attribution, :license, :as_of, :notice, :total

    def initialize(data:, attribution: nil, license: nil, as_of: nil, notice: nil, total: nil)
      @data = data
      @attribution = attribution
      @license = license
      @as_of = as_of
      @notice = notice
      @total = total
    end
  end

  # One catalogue detail: the listing fields, a pricing table, and citation.
  Space = Struct.new(
    :slug,
    :title,
    :city_slug,
    :zone_slug,
    :operator_slug,
    :operator_name,
    :country_code,
    :lat,
    :lng,
    :featured,
    :market_verdict,
    :market_median,
    :market_sample_size,
    :url,
    :updated_at,
    :address,
    :capacity,
    :amenities,
    :pricing,
    :attribution,
    :notice,
    keyword_init: true
  )

  # Client for the public CoworkingView API.
  #
  # The API needs no key. Creating a client does not touch the network. Calls
  # use three endpoints only:
  #
  # - +GET /v1/market/rates+ — Price Index (+rates+, +cities+)
  # - +GET /v1/properties+ — catalogue search (+spaces+)
  # - +GET /v1/properties/{slug}+ — one space (+space+)
  #
  # On HTTP 429 or 5xx the client waits +Retry-After+ seconds, else
  # +RateLimit-Reset+, else 2 seconds, and never more than 10, then tries once
  # more.
  class Client
    DEFAULT_BASE_URL = "https://api.coworkingview.com"
    ENV_BASE_URL = "COWORKINGVIEW_API_URL"
    DEFAULT_TIMEOUT = 20
    DEFAULT_USER_AGENT = "coworkingview-ruby/#{VERSION} (+https://github.com/coworkingview/flex-office-data)".freeze
    FALLBACK_WAIT = 2.0
    MAX_WAIT = 10.0
    MAX_LIMIT = 200
    PAGE_SIZE = 50
    LOW_CONFIDENCE_BELOW = 10

    LOCALES = %w[en es de].freeze
    CURRENCIES = %w[EUR GBP USD CHF AED VES].freeze
    PRODUCTS = %w[
      flex_desk fix_desk private_office exclusive_bereich day_pass
      meeting_room event_space virtual_office membership
    ].freeze
    SORTS = %w[random price-asc date-desc date-asc].freeze
    PRODUCT_ORDER = PRODUCTS
    STAT_UNITS = {
      "day_pass" => "day",
      "meeting_room" => "hour",
      "event_space" => "hour",
      "virtual_office" => "month"
    }.freeze
    WORKSPACE_PATH = { "en" => "workspace", "es" => "oficina", "de" => "buero" }.freeze
    SITE_URL = "https://coworkingview.com"
    SLUG_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

    RATE_COLUMNS = %i[
      city_slug city_name country_code currency product unit median p25 p75
      sample_size property_count operator_count low_confidence as_of
    ].freeze
    CITY_COLUMNS = %i[
      city_slug city_name country_code currency published property_count
      operator_count entry_median entry_min entry_max p25 p75 sample_size as_of
    ].freeze

    attr_reader :base_url, :timeout, :user_agent

    def initialize(base_url: nil, timeout: DEFAULT_TIMEOUT, user_agent: nil, sleeper: nil)
      @base_url = resolve_base_url(base_url)
      @timeout = check_timeout(timeout)
      @user_agent = check_user_agent(user_agent)
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect} timeout=#{@timeout.inspect}>"
    end

    # Price Index figures, one row per published city and product.
    #
    # +GET /v1/market/rates+. Unpublished cities produce no rows. A product the
    # API adds later is kept, so a new aggregate does not need a new release.
    def rates(city: nil, country: nil, currency: nil, locale: "en")
      path = "/v1/market/rates"
      payload = get(path, market_query(city, country, currency, locale))
      data = object_data(payload, path)
      rows = guarded(path) { rate_rows(data) }
      index_dataset(rows, data)
    end

    # Cities of the Price Index, published cities first.
    #
    # Same request as #rates.
    def cities(city: nil, country: nil, currency: nil, locale: "en")
      path = "/v1/market/rates"
      payload = get(path, market_query(city, country, currency, locale))
      data = object_data(payload, path)
      rows = guarded(path) { city_rows(data) }
      index_dataset(rows, data)
    end

    # Catalogue search. One row per space, at most 200.
    #
    # +GET /v1/properties+. Pages are followed until +limit+ rows or the last
    # page. Page size is +min(50, limit)+. With +sort+ +random+, the seed of
    # the first page is sent again on the following pages.
    def spaces(
      city: nil,
      country: nil,
      zone: nil,
      operator: nil,
      product: nil,
      min_capacity: nil,
      min_price: nil,
      max_price: nil,
      currency: nil,
      sort: "random",
      limit: 50,
      locale: "en",
      seed: nil
    )
      path = "/v1/properties"
      request_locale = check_locale(locale)
      request_sort = check_sort(sort)
      request_limit = check_limit(limit)
      low = check_price("min_price", min_price)
      high = check_price("max_price", max_price)
      check_price_range(low, high)
      user_seed = check_seed(seed)
      params = {
        "locale" => request_locale,
        "city" => check_text("city", city),
        "country" => check_text("country", country),
        "zone" => check_text("zone", zone),
        "operator" => check_text("operator", operator),
        "pricingOptionType" => check_product(product),
        "minCapacity" => check_count("min_capacity", min_capacity),
        "minPrice" => low,
        "maxPrice" => high,
        "currency" => check_currency(currency),
        "sortBy" => request_sort,
        "pageSize" => [PAGE_SIZE, request_limit].min
      }
      params["seed"] = user_seed unless user_seed.nil?

      cards = []
      first_meta = {}
      total = nil
      page = 1
      loop do
        payload = get(path, params.merge("page" => page))
        data = list_data(payload, path)
        meta = meta_of(payload)
        pagination = meta["pagination"]
        pagination = {} unless pagination.is_a?(Hash)
        if page == 1
          first_meta = meta
          total = pagination["total"]
          if request_sort == "random" && user_seed.nil? && !meta["seed"].nil?
            params["seed"] = meta["seed"]
          end
        end
        data.each { |card| cards << card if card.is_a?(Hash) }
        page_count = pagination["pageCount"]
        break if cards.length >= request_limit || data.empty? || !page_count.is_a?(Integer) || page >= page_count

        page += 1
      end

      rows = guarded(path) { cards.take(request_limit).map { |card| space_row(card, request_locale) } }
      notice = first_meta["catalogueNotice"]
      Dataset.new(
        data: rows,
        attribution: citation_text(first_meta),
        notice: notice.is_a?(String) ? notice : nil,
        total: total
      )
    end

    # One space and its pricing table.
    #
    # +GET /v1/properties/{slug}+. The slug is checked before it is put in the path.
    def space(slug, locale: "en")
      request_locale = check_locale(locale)
      path = "/v1/properties/#{check_slug(slug)}"
      payload = get(path, { "locale" => request_locale })
      detail = object_data(payload, path)
      meta = meta_of(payload)
      notice = meta["catalogueNotice"]
      guarded(path) do
        fields = space_row(detail, request_locale)
        web_url = detail["webUrl"]
        fields[:url] = web_url if web_url.is_a?(String) && !web_url.empty?
        fields[:address] = detail["address"]
        capacity = detail["capacity"]
        fields[:capacity] = capacity.is_a?(Integer) ? capacity : nil
        amenities = detail["amenities"]
        fields[:amenities] = amenities.is_a?(Array) ? amenities.map(&:to_s) : []
        fields[:pricing] = pricing_rows(detail)
        fields[:attribution] = citation_text(meta)
        fields[:notice] = notice.is_a?(String) ? notice : nil
        Space.new(**fields)
      end
    end

    def self.retry_wait(headers, now: Time.now)
      wait = delay_seconds(header_value(headers, "Retry-After"), now: now)
      wait = delay_seconds(header_value(headers, "RateLimit-Reset"), now: now) if wait.nil?
      wait = FALLBACK_WAIT if wait.nil?
      [wait, MAX_WAIT].min
    end

    def self.header_value(headers, name)
      return nil if headers.nil?

      headers.each do |key, value|
        return value if key.to_s.casecmp?(name)
      end
      nil
    end

    def self.delay_seconds(value, now:)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?
      return [0.0, text.to_f].max if /\A-?\d+(?:\.\d+)?\z/.match?(text)

      begin
        moment = Time.httpdate(text)
      rescue ArgumentError
        return nil
      end
      delta = moment - now
      delta.negative? ? 0.0 : delta.to_f
    end
    private_class_method :delay_seconds

    private

    def resolve_base_url(base_url)
      raw = blank?(base_url) ? ENV.fetch(ENV_BASE_URL, nil) : base_url
      raw = DEFAULT_BASE_URL if blank?(raw)
      unless raw.is_a?(String)
        raise ArgumentError, "base_url must be an http(s) URL, got #{raw.inspect}."
      end

      stripped = raw.strip.sub(%r{/+\z}, "")
      uri = URI.parse(stripped)
      unless %w[http https].include?(uri.scheme) && uri.host && uri.userinfo.nil?
        raise ArgumentError, "base_url must be an http(s) origin without userinfo."
      end
      unless uri.path.nil? || uri.path.empty?
        raise ArgumentError, "base_url must be an origin without a path."
      end
      unless uri.query.nil? && uri.fragment.nil?
        raise ArgumentError, "base_url must be an origin without a query or fragment."
      end

      stripped
    rescue URI::InvalidURIError
      raise ArgumentError, "base_url must be an http(s) origin without userinfo."
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end

    def check_timeout(value)
      unless (value.is_a?(Integer) || value.is_a?(Float)) && value.positive?
        raise ArgumentError, "timeout must be a positive number of seconds, got #{value.inspect}."
      end

      value.to_f
    end

    def check_user_agent(value)
      return DEFAULT_USER_AGENT if blank?(value)
      unless value.is_a?(String)
        raise ArgumentError, "user_agent must be a string, got #{value.inspect}."
      end
      if /[\r\n]/.match?(value)
        raise ArgumentError, "user_agent must be a single line."
      end

      value.strip
    end

    def market_query(city, country, currency, locale)
      {
        "locale" => check_locale(locale),
        "city" => check_text("city", city),
        "country" => check_text("country", country),
        "currency" => check_currency(currency)
      }
    end

    def get(path, params)
      uri = build_uri(path, params)
      attempt = 0
      loop do
        attempt += 1
        status, headers, body, reason = perform(uri)
        return parse_object(status, body, path) if status.between?(200, 299)
        raise problem(status, reason, body) unless attempt == 1 && retryable?(status)

        @sleeper.call(self.class.retry_wait(headers))
      end
    end

    def build_uri(path, params)
      cleaned = []
      params.each do |key, value|
        next if value.nil?

        cleaned << [key.to_s, value]
      end
      query = URI.encode_www_form(cleaned)
      url = +"#{@base_url}#{path}"
      url << "?#{query}" unless query.empty?
      URI.parse(url)
    end

    def perform(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout
      http.max_retries = 0 if http.respond_to?(:max_retries=)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = @user_agent
      response = http.request(request)
      [response.code.to_i, header_map(response), response.body.to_s, response.message.to_s]
    rescue Timeout::Error => e
      raise Error.new("Could not reach #{@base_url}: #{e.message}", status: 0, code: "TIMEOUT")
    rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error.new("Could not reach #{@base_url}: #{e.message}", status: 0, code: "CONNECTION")
    end

    def header_map(response)
      headers = {}
      response.each_header { |key, value| headers[key] = value }
      headers
    end

    def retryable?(status)
      status == 429 || status.between?(500, 599)
    end

    def parse_json(raw)
      text = raw.to_s.dup
      text.force_encoding(Encoding::UTF_8)
      raise JSON::ParserError, "invalid encoding" unless text.valid_encoding?

      JSON.parse(text)
    end

    def parse_object(status, body, path)
      begin
        payload = parse_json(body)
      rescue JSON::ParserError
        raise bad_response(status, "The API returned a body that is not valid JSON", "GET #{path}")
      end
      unless payload.is_a?(Hash)
        raise bad_response(status, "The API returned JSON that is not an object", "GET #{path}")
      end

      payload
    end

    def problem(status, reason, raw)
      body = {}
      begin
        parsed = parse_json(raw)
        body = parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        body = {}
      end
      title = body["title"]
      detail = body["detail"]
      code = body["code"]
      APIError.new(
        status: status,
        code: code.is_a?(String) && !code.empty? ? code : "HTTP_#{status}",
        title: title.is_a?(String) && !title.empty? ? title : (reason.empty? ? "HTTP #{status}" : reason),
        detail: detail.is_a?(String) ? detail : nil,
        errors: body["errors"]
      )
    end

    def bad_response(status, title, detail)
      APIError.new(status: status, code: "BAD_RESPONSE", title: title, detail: detail)
    end

    def object_data(payload, path)
      unless payload.key?("data")
        raise bad_response(200, "The API response has no 'data' member", "GET #{path}")
      end
      data = payload["data"]
      return data if data.is_a?(Hash)

      raise bad_response(200, "Unexpected shape for GET #{path}", "data is not an object")
    end

    def list_data(payload, path)
      unless payload.key?("data")
        raise bad_response(200, "The API response has no 'data' member", "GET #{path}")
      end
      data = payload["data"]
      return data if data.is_a?(Array)

      raise bad_response(200, "Unexpected shape for GET #{path}", "data is not an array")
    end

    def guarded(path)
      yield
    rescue KeyError, NoMethodError, TypeError => e
      raise bad_response(200, "Unexpected shape for GET #{path}", e.message)
    end

    def meta_of(payload)
      meta = payload["meta"]
      meta.is_a?(Hash) ? meta : {}
    end

    def citation_text(meta)
      citation = meta["citation"]
      return nil unless citation.is_a?(Hash)

      text = citation["text"]
      text.is_a?(String) ? text : nil
    end

    def index_dataset(rows, data)
      attribution = data["attribution"]
      license = data["licenseUrl"]
      as_of = data["asOf"]
      Dataset.new(
        data: rows,
        attribution: attribution.is_a?(String) ? attribution : nil,
        license: license.is_a?(String) ? license : nil,
        as_of: as_of.is_a?(String) ? as_of : nil
      )
    end

    def money_amount(money)
      return nil if money.nil?

      money.fetch("amount")
    end

    def sub(object, key)
      return nil unless object.is_a?(Hash)

      object[key]
    end

    def snake(key)
      key.to_s.gsub(/(?<!^)(?=[A-Z])/, "_").downcase
    end

    def stat?(value)
      value.is_a?(Hash) && value.key?("median") && value.key?("sampleSize")
    end

    def product_sort_key(product)
      index = PRODUCT_ORDER.index(product)
      index ? [0, index, ""] : [1, 0, product.to_s]
    end

    def rate_rows(data)
      rows = []
      cities = data["cities"]
      cities = [] unless cities.is_a?(Array)
      cities.each do |city|
        next unless city.is_a?(Hash)

        place = city.fetch("city")
        base = {
          city_slug: place.fetch("slug"),
          city_name: place.fetch("name"),
          country_code: city["countryCode"],
          currency: city.fetch("currency")
        }
        figures = city["figures"]
        by_type = city["byType"]
        items = if figures.is_a?(Array) && !figures.empty?
                  figures
                elsif by_type.is_a?(Array)
                  by_type
                else
                  []
                end
        items.each do |item|
          next unless item.is_a?(Hash)

          rows << base.merge(
            product: item.fetch("optionType"),
            unit: "month",
            median: money_amount(item.fetch("median")),
            p25: money_amount(item["p25"]),
            p75: money_amount(item["p75"]),
            sample_size: item.fetch("sampleSize"),
            property_count: item["propertyCount"],
            operator_count: item["operatorCount"]
          )
        end
        city.each do |key, value|
          next unless stat?(value)

          product = snake(key)
          rows << base.merge(
            product: product,
            unit: STAT_UNITS[product],
            median: money_amount(value.fetch("median")),
            p25: money_amount(value["p25"]),
            p75: money_amount(value["p75"]),
            sample_size: value.fetch("sampleSize"),
            property_count: value["propertyCount"],
            operator_count: value["operatorCount"]
          )
        end
      end
      as_of = data["asOf"]
      rows.each do |row|
        row[:low_confidence] = row[:sample_size] < LOW_CONFIDENCE_BELOW
        row[:as_of] = as_of
      end
      rows.sort_by! { |row| [row[:city_slug].to_s, product_sort_key(row[:product])] }
      rows.map { |row| RATE_COLUMNS.to_h { |column| [column, row[column]] } }
    end

    def city_rows(data)
      as_of = data["asOf"]
      rows = []
      cities = data["cities"]
      cities = [] unless cities.is_a?(Array)
      cities.each do |city|
        next unless city.is_a?(Hash)

        place = city.fetch("city")
        rows << {
          city_slug: place.fetch("slug"),
          city_name: place.fetch("name"),
          country_code: city["countryCode"],
          currency: city["currency"],
          published: true,
          property_count: city["propertyCount"],
          operator_count: city["operatorCount"],
          entry_median: money_amount(city["entryMedian"]),
          entry_min: money_amount(city["entryMin"]),
          entry_max: money_amount(city["entryMax"]),
          p25: money_amount(city["p25"]),
          p75: money_amount(city["p75"]),
          sample_size: city["sampleSize"],
          as_of: as_of
        }
      end
      unpublished = data["unpublished"]
      unpublished = [] unless unpublished.is_a?(Array)
      unpublished.each do |city|
        next unless city.is_a?(Hash)

        place = city.fetch("city")
        rows << {
          city_slug: place.fetch("slug"),
          city_name: place.fetch("name"),
          country_code: city["countryCode"],
          currency: city["currency"],
          published: false,
          property_count: nil,
          operator_count: nil,
          entry_median: nil,
          entry_min: nil,
          entry_max: nil,
          p25: nil,
          p75: nil,
          sample_size: nil,
          as_of: as_of
        }
      end
      rows.sort_by! { |row| [row[:published] ? 0 : 1, row[:city_slug].to_s] }
      rows.map { |row| CITY_COLUMNS.to_h { |column| [column, row[column]] } }
    end

    def listing_url(slug, locale)
      "#{SITE_URL}/#{locale}/#{WORKSPACE_PATH.fetch(locale)}/#{slug}"
    end

    def space_row(card, locale)
      market = card["marketPosition"]
      market = {} unless market.is_a?(Hash)
      {
        slug: card.fetch("slug"),
        title: card.fetch("title"),
        city_slug: sub(card["city"], "slug"),
        zone_slug: sub(card["zone"], "slug"),
        operator_slug: sub(card["operator"], "slug"),
        operator_name: sub(card["operator"], "name"),
        country_code: card["countryCode"],
        lat: sub(card["coordinates"], "lat"),
        lng: sub(card["coordinates"], "lng"),
        featured: card["featured"],
        market_verdict: market["verdict"],
        market_median: money_amount(market["median"]),
        market_sample_size: market["sampleSize"],
        url: listing_url(card.fetch("slug"), locale),
        updated_at: card["updatedAt"]
      }
    end

    def pricing_rows(detail)
      options = detail["pricingOptions"]
      options = [] unless options.is_a?(Array)
      options.filter_map do |option|
        next unless option.is_a?(Hash)

        price = option["price"]
        {
          product: option.fetch("optionType"),
          title: option.fetch("title"),
          price: money_amount(price),
          currency: price.nil? ? nil : price.fetch("currency"),
          billing_period: option.fetch("billingPeriod"),
          price_on_request: option.fetch("priceOnRequest"),
          min_capacity: option["minCapacity"],
          max_capacity: option["maxCapacity"]
        }
      end
    end

    def check_one_of(name, value, valid)
      unless value.is_a?(String) && valid.include?(value)
        choices = valid.map(&:inspect).join(", ")
        raise ArgumentError, "#{name}=#{value.inspect} is not supported; use one of #{choices}."
      end

      value
    end

    def check_locale(value)
      check_one_of("locale", value, LOCALES)
    end

    def check_currency(value)
      return nil if value.nil?

      normalised = value.is_a?(String) ? value.upcase : value
      check_one_of("currency", normalised, CURRENCIES)
    end

    def check_product(value)
      return nil if value.nil?

      check_one_of("product", value, PRODUCTS)
    end

    def check_sort(value)
      check_one_of("sort", value, SORTS)
    end

    def check_text(name, value)
      return nil if value.nil?
      unless value.is_a?(String) && !value.strip.empty?
        raise ArgumentError, "#{name} must be a non-empty string, got #{value.inspect}."
      end

      value.strip
    end

    def check_limit(value)
      unless value.is_a?(Integer) && value >= 1
        raise ArgumentError, "limit must be a positive integer, got #{value.inspect}."
      end
      if value > MAX_LIMIT
        raise ArgumentError,
              "limit=#{value} exceeds the maximum of #{MAX_LIMIT}. The catalogue may be " \
              "searched and linked to, not bulk-copied: its content belongs to the operators " \
              "and the API's catalogue notice forbids systematic extraction. Narrow the " \
              "search (city, zone, operator, product, price) instead."
      end

      value
    end

    def check_count(name, value)
      return nil if value.nil?
      unless value.is_a?(Integer) && value >= 0
        raise ArgumentError, "#{name} must be a non-negative integer, got #{value.inspect}."
      end

      value
    end

    def check_price(name, value)
      return nil if value.nil?
      unless (value.is_a?(Integer) || value.is_a?(Float)) && value >= 0
        raise ArgumentError, "#{name} must be a non-negative number, got #{value.inspect}."
      end

      value
    end

    def check_price_range(min_price, max_price)
      return if min_price.nil? || max_price.nil? || min_price <= max_price

      raise ArgumentError, "min_price (#{min_price}) is greater than max_price (#{max_price})."
    end

    def check_slug(value)
      unless value.is_a?(String) && SLUG_PATTERN.match?(value)
        raise ArgumentError,
              "slug=#{value.inspect} is not a valid slug; slugs are letters, digits, '.', '_' " \
              "and '-', starting with a letter or digit (e.g. 'sankt-oberholz-rosenthaler-berlin')."
      end

      value
    end

    def check_seed(value)
      return nil if value.nil?
      return value if value.is_a?(Integer) && value >= 0
      return value.strip if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, "seed must be a non-negative integer or a non-empty string, got #{value.inspect}."
    end
  end
end
