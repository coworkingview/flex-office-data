# frozen_string_literal: true

module RedmineCoworkingview
  # One Price Index row: a city and a product.
  #
  # Column meanings match spec/SPEC.md section 3 and CoworkingView::Client#rates
  # in the Ruby gem. Unpublished cities are not rows.
  Rate = Struct.new(
    :city_slug,
    :city_name,
    :country_code,
    :currency,
    :product,
    :unit,
    :median,
    :p25,
    :p75,
    :sample_size,
    :property_count,
    :operator_count,
    :low_confidence,
    :as_of,
    keyword_init: true
  )

  # Rows plus the citation fields that travel with a rates response.
  class Dataset
    attr_reader :rows, :attribution, :license, :as_of, :source

    def initialize(rows:, attribution: nil, license: nil, as_of: nil, source:)
      @rows = rows
      @attribution = attribution
      @license = license
      @as_of = as_of
      @source = source
    end

    def self.from_api(payload)
      unless payload.is_a?(Hash) && payload["data"].is_a?(Hash)
        raise Error, "The rates response has no data object"
      end

      data = payload["data"]
      rows = rows_from_cities(data)
      new(
        rows: rows,
        attribution: text_or_nil(data["attribution"]),
        license: text_or_nil(data["licenseUrl"]),
        as_of: text_or_nil(data["asOf"]),
        source: "live"
      )
    rescue KeyError, TypeError, NoMethodError => e
      raise Error, "Unexpected rates payload: #{e.message}"
    end

    def self.from_csv(path)
      rows = []
      CSV.foreach(path, headers: true, encoding: "UTF-8") do |record|
        sample_size = integer_field(record["sample_size"])
        rows << Rate.new(
          city_slug: text_or_nil(record["city_slug"]),
          city_name: text_or_nil(record["city_name"]),
          country_code: text_or_nil(record["country_code"]),
          currency: text_or_nil(record["currency"]),
          product: text_or_nil(record["product"]),
          unit: text_or_nil(record["unit"]),
          median: number_field(record["median"]),
          p25: number_field(record["p25"]),
          p75: number_field(record["p75"]),
          sample_size: sample_size,
          property_count: integer_field(record["property_count"]),
          operator_count: integer_field(record["operator_count"]),
          low_confidence: !sample_size.nil? && sample_size < LOW_CONFIDENCE_BELOW,
          as_of: text_or_nil(record["as_of"])
        )
      end
      as_of = rows.empty? ? nil : rows.first.as_of
      new(rows: rows, as_of: as_of, source: "snapshot")
    end

    def self.rows_from_cities(data)
      as_of = data["asOf"]
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
      rows.each do |row|
        row[:low_confidence] = row[:sample_size] < LOW_CONFIDENCE_BELOW
        row[:as_of] = as_of
      end
      rows.sort_by! { |row| [row[:city_slug].to_s, product_sort_key(row[:product])] }
      rows.map { |row| Rate.new(**row) }
    end

    def self.money_amount(money)
      return nil if money.nil?

      money.fetch("amount")
    end

    def self.stat?(value)
      value.is_a?(Hash) && value.key?("median") && value.key?("sampleSize")
    end

    def self.snake(key)
      key.to_s.gsub(/(?<!^)(?=[A-Z])/, "_").downcase
    end

    def self.product_sort_key(product)
      index = PRODUCTS.index(product)
      index ? [0, index, ""] : [1, 0, product.to_s]
    end

    def self.text_or_nil(value)
      return nil if value.nil?

      text = value.to_s
      text.strip.empty? ? nil : text
    end

    def self.number_field(value)
      text = text_or_nil(value)
      return nil if text.nil?
      return text.to_i if /\A-?\d+\z/.match?(text)
      return text.to_f if /\A-?\d+\.\d+\z/.match?(text)

      raise Error, "Snapshot has a non-numeric amount"
    end

    def self.integer_field(value)
      text = text_or_nil(value)
      return nil if text.nil?
      return text.to_i if /\A-?\d+\z/.match?(text)

      raise Error, "Snapshot has a non-integer count"
    end

    private_class_method :rows_from_cities, :money_amount, :stat?, :snake,
                         :product_sort_key, :text_or_nil, :number_field, :integer_field
  end
end
