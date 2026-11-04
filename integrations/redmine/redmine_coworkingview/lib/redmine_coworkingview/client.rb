# frozen_string_literal: true

module RedmineCoworkingview
  # GET /v1/market/rates. Locale is required; the API returns 400 without it.
  #
  # Pass +http+ as +->(uri) { [status, body, headers] }+ to avoid the network.
  # The default transport is +Net::HTTP+ with open, read and write timeouts.
  class Client
    DEFAULT_BASE_URL = "https://api.coworkingview.com"
    ENV_BASE_URL = "COWORKINGVIEW_API_URL"
    DEFAULT_TIMEOUT = 20
    USER_AGENT = "redmine_coworkingview/#{VERSION} (+https://github.com/coworkingview/flex-office-data)".freeze
    FALLBACK_WAIT = 2.0
    MAX_WAIT = 10.0

    attr_reader :base_url, :timeout, :user_agent

    def initialize(base_url: nil, timeout: DEFAULT_TIMEOUT, user_agent: nil, http: nil, sleeper: nil)
      @base_url = resolve_base_url(base_url)
      @timeout = timeout
      unless @timeout.is_a?(Numeric) && @timeout.positive?
        raise ArgumentError, "timeout must be a positive number of seconds"
      end
      @user_agent = user_agent.nil? || user_agent.to_s.strip.empty? ? USER_AGENT : user_agent.to_s.strip
      @http = http
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def rates(locale:)
      request_locale = check_locale(locale)
      payload = get("/v1/market/rates", { "locale" => request_locale })
      Dataset.from_api(payload)
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout if http.respond_to?(:write_timeout=)
      http.max_retries = 0 if http.respond_to?(:max_retries=)
      http
    end

    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = @user_agent
      request
    end

    private

    def check_locale(locale)
      text = locale.to_s.strip.downcase
      return text if LOCALES.include?(text)

      raise ArgumentError, "locale must be one of #{LOCALES.join(', ')}"
    end

    def get(path, params)
      uri = build_uri(path, params)
      attempt = 0
      loop do
        attempt += 1
        status, body, headers = perform(uri)
        return parse_object(status, body) if status.between?(200, 299)
        raise http_error(status, body) unless attempt == 1 && retryable?(status)

        @sleeper.call(retry_wait(headers))
      end
    end

    def build_uri(path, params)
      query = URI.encode_www_form(params)
      URI.parse("#{@base_url}#{path}?#{query}")
    end

    def perform(uri)
      if @http
        status, body, headers = @http.call(uri)
        return [status.to_i, body.to_s, headers.is_a?(Hash) ? headers : {}]
      end

      response = build_http(uri).request(build_request(uri))
      headers = {}
      response.each_header { |key, value| headers[key] = value }
      [response.code.to_i, response.body.to_s, headers]
    rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error, "Could not reach #{@base_url}: #{e.message}"
    end

    def retryable?(status)
      status == 429 || status.between?(500, 599)
    end

    def retry_wait(headers)
      wait = delay_seconds(header_value(headers, "Retry-After"))
      wait = delay_seconds(header_value(headers, "RateLimit-Reset")) if wait.nil?
      wait = FALLBACK_WAIT if wait.nil?
      [[wait, 0.0].max, MAX_WAIT].min
    end

    def header_value(headers, name)
      return nil unless headers.is_a?(Hash)

      headers.each do |key, value|
        return value if key.to_s.casecmp?(name)
      end
      nil
    end

    def delay_seconds(value)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?
      return [0.0, text.to_f].max if /\A-?\d+(?:\.\d+)?\z/.match?(text)

      begin
        delta = Time.httpdate(text) - Time.now
      rescue ArgumentError
        return nil
      end
      delta.negative? ? 0.0 : delta.to_f
    end

    def parse_object(status, body)
      payload = JSON.parse(body.to_s)
      return payload if payload.is_a?(Hash)

      raise Error.new("The rates response is not a JSON object", status: status)
    rescue JSON::ParserError
      raise Error.new("The rates response is not valid JSON", status: status)
    end

    def http_error(status, body)
      title = "HTTP #{status}"
      begin
        parsed = JSON.parse(body.to_s)
        if parsed.is_a?(Hash) && parsed["title"].is_a?(String) && !parsed["title"].empty?
          title = parsed["title"]
        end
      rescue JSON::ParserError
        title = "HTTP #{status}"
      end
      Error.new(title, status: status)
    end

    def resolve_base_url(base_url)
      raw = base_url
      raw = ENV.fetch(ENV_BASE_URL, nil) if blank?(raw)
      raw = DEFAULT_BASE_URL if blank?(raw)
      stripped = raw.to_s.strip.sub(%r{/+\z}, "")
      uri = URI.parse(stripped)
      unless %w[http https].include?(uri.scheme) && uri.host && uri.userinfo.nil?
        raise ArgumentError, "base_url must be an http(s) origin"
      end
      unless (uri.path.nil? || uri.path.empty?) && uri.query.nil? && uri.fragment.nil?
        raise ArgumentError, "base_url must be an origin without a path, query or fragment"
      end

      stripped
    rescue URI::InvalidURIError
      raise ArgumentError, "base_url must be an http(s) origin"
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
    end
  end
end
