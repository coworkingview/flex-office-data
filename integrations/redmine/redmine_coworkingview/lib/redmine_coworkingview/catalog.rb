# frozen_string_literal: true

module RedmineCoworkingview
  # Live rates, cached, with the bundled CSV when the network is off or the
  # request fails. A failure is not written to the cache.
  class Catalog
    def initialize(client:, settings:, cache: nil, snapshot_path: SNAPSHOT_PATH, logger: nil)
      @client = client
      @settings = settings
      @cache = cache
      @snapshot_path = snapshot_path
      @logger = logger
    end

    def dataset
      return load_snapshot unless @settings.network?

      cached = read_cache
      return cached if cached

      begin
        live = @client.rates(locale: @settings.locale)
      rescue Error => e
        log("rates request failed: #{e.message}")
        return load_snapshot
      end

      write_cache(live)
      live
    end

    private

    def cache_key
      "redmine_coworkingview/rates/#{VERSION}/#{@settings.locale}"
    end

    def read_cache
      return nil unless @cache.respond_to?(:read)

      value = @cache.read(cache_key)
      value.is_a?(Dataset) ? value : nil
    rescue StandardError => e
      log("cache read failed: #{e.message}")
      nil
    end

    def write_cache(dataset)
      return unless @cache.respond_to?(:write)

      @cache.write(cache_key, dataset, expires_in: @settings.cache_ttl_hours * 3600)
    rescue StandardError => e
      log("cache write failed: #{e.message}")
      nil
    end

    def load_snapshot
      Dataset.from_csv(@snapshot_path)
    rescue Error
      raise
    rescue StandardError => e
      log("snapshot unreadable: #{e.message}")
      raise Error, "Price Index snapshot is unreadable"
    end

    def log(message)
      return unless @logger.respond_to?(:warn)

      @logger.warn("redmine_coworkingview: #{message}")
    rescue StandardError
      nil
    end
  end
end
