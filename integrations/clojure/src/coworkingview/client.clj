(ns coworkingview.client
  "Optional client for the public Price Index API.

  The endpoint is `GET /v1/market/rates`, the read-only API documented in
  spec/SPEC.md. No API key. Nothing is requested when this namespace loads.
  When the request fails, [[price-index]] returns the bundled snapshot from
  [[coworkingview.core/snapshot]]. A currency filter is never converted
  locally: rows in another currency are left out rather than rewritten."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [coworkingview.core :as core])
  (:import [java.net URI]
           [java.net.http HttpClient HttpClient$Redirect HttpRequest HttpResponse$BodyHandlers]
           [java.time Duration ZoneOffset ZonedDateTime]
           [java.time.format DateTimeFormatter DateTimeParseException]))

(set! *warn-on-reflection* true)

(def user-agent
  "User-Agent sent to the public API."
  "coworkingview-clojure/0.1.0 (+https://github.com/coworkingview/flex-office-data)")

(def default-base-url
  "Public API origin used when `COWORKINGVIEW_API_URL` is unset."
  "https://api.coworkingview.com")

(def ^:private locales #{"en" "es" "de"})

(def ^:private currencies #{"EUR" "GBP" "USD" "CHF" "AED" "VES"})

(def ^:private product-order
  ["flex_desk" "fix_desk" "private_office" "exclusive_bereich"
   "day_pass" "meeting_room" "event_space" "virtual_office" "membership"])

(def ^:private stat-units
  {"day_pass" "day"
   "meeting_room" "hour"
   "event_space" "hour"
   "virtual_office" "month"})

(def ^:private rate-columns
  [:city_slug :city_name :country_code :currency :product :unit
   :median :p25 :p75 :sample_size :property_count :operator_count
   :low_confidence :as_of])

(def ^:private city-columns
  [:city_slug :city_name :country_code :currency :published
   :property_count :operator_count :entry_median :entry_min :entry_max
   :p25 :p75 :sample_size :as_of])

(defn- env
  ^String [name]
  (System/getenv name))

(defn- caller-error
  [message data]
  (throw (ex-info message (assoc data :coworkingview/caller-error true))))

(defn- caller-error?
  [exception]
  (boolean (:coworkingview/caller-error (ex-data exception))))

(defn resolve-base-url
  "API origin. An explicit URL wins, then `COWORKINGVIEW_API_URL`, then the public API.

  A trailing slash is removed. Blank values are ignored."
  ([]
   (resolve-base-url nil))
  ([explicit]
   (let [from-env (env "COWORKINGVIEW_API_URL")
         chosen (or (not-empty (some-> explicit str str/trim))
                    (not-empty (some-> from-env str str/trim))
                    default-base-url)]
     (str/replace chosen #"/+$" ""))))

(defn- validate-locale
  [locale]
  (let [value (if (nil? locale) "en" (str/lower-case (str/trim (str locale))))]
    (if (locales value)
      value
      (caller-error "locale is not supported. Use en, es or de."
                    {:locale locale}))))

(defn- validate-currency
  [currency]
  (when (some? currency)
    (let [value (str/upper-case (str/trim (str currency)))]
      (if (currencies value)
        value
        (caller-error "currency is not supported. Use EUR, GBP, USD, CHF, AED or VES."
                      {:currency currency})))))

(defn- optional-text
  [name value]
  (when (some? value)
    (let [text (str/trim (str value))]
      (if (str/blank? text)
        (caller-error (str name " must be a non-empty string.") {name value})
        text))))

(defn- query-string
  [params]
  (->> params
       (remove (fn [[_ value]] (nil? value)))
       (map (fn [[k value]]
              (str (java.net.URLEncoder/encode (name k) "UTF-8")
                   "="
                   (java.net.URLEncoder/encode (str value) "UTF-8"))))
       (str/join "&")))

(defn- endpoint
  [{:keys [base-url locale city country currency]}]
  (str (resolve-base-url base-url)
       "/v1/market/rates?"
       (query-string {"locale" (validate-locale locale)
                      "city" (optional-text "city" city)
                      "country" (optional-text "country" country)
                      "currency" (validate-currency currency)})))

(defn- header-value
  [headers name]
  (when headers
    (some (fn [[k value]]
            (when (= (str/lower-case (str k)) name)
              (cond
                (sequential? value) (first value)
                (nil? value) nil
                :else (str value))))
          headers)))

(defn- header-seconds
  "Delay from a Retry-After or RateLimit-Reset value: seconds, or an HTTP date.

  Returns nil when the text is missing or not a delay."
  [value]
  (when-not (str/blank? (str value))
    (let [text (str/trim (str value))]
      (if (re-matches #"-?\d+(?:\.\d+)?" text)
        (max 0.0 (Double/parseDouble text))
        (try
          (let [parsed (ZonedDateTime/parse text DateTimeFormatter/RFC_1123_DATE_TIME)
                now (ZonedDateTime/now ZoneOffset/UTC)
                seconds (.toSeconds (Duration/between now parsed))]
            (double (max 0 seconds)))
          (catch DateTimeParseException _ nil))))))

(defn- retry-wait
  "Seconds to wait before the single retry. Capped at 10.

  Uses Retry-After, otherwise RateLimit-Reset, otherwise 2 seconds."
  [headers]
  (let [wait (or (header-seconds (header-value headers "retry-after"))
                 (header-seconds (header-value headers "ratelimit-reset"))
                 2.0)]
    (min 10.0 (double wait))))

(defn- default-sleep
  [seconds]
  (Thread/sleep (long (Math/ceil (* 1000.0 (double seconds))))))

(defn- headers->map
  [^java.net.http.HttpHeaders headers]
  (into {}
        (map (fn [[k vs]]
               [(str/lower-case (str k)) (first vs)]))
        (.map headers)))

(defn- http-get
  "One GET. `request` is a map of `:url` and `:headers`. Used unless a test double is passed."
  [{:keys [url headers]}]
  (let [^HttpClient client (-> (HttpClient/newBuilder)
                               (.connectTimeout (Duration/ofSeconds 20))
                               (.followRedirects HttpClient$Redirect/NEVER)
                               (.build))
        builder (HttpRequest/newBuilder)]
    (.uri builder (URI/create url))
    (.timeout builder (Duration/ofSeconds 20))
    (.GET builder)
    (doseq [[k v] headers]
      (.header builder (str k) (str v)))
    (let [response (.send client
                          ^HttpRequest (.build builder)
                          (HttpResponse$BodyHandlers/ofString))]
      {:status (.statusCode response)
       :body (.body response)
       :headers (headers->map (.headers response))})))

(defn- snake
  [key]
  (-> (str key)
      (str/replace #"(?<!^)(?=[A-Z])" "_")
      str/lower-case))

(defn- amount
  [money]
  (cond
    (nil? money) nil
    (and (map? money) (contains? money "amount")) (get money "amount")
    :else (throw (ex-info "A money object has no amount." {}))))

(defn- stat?
  [value]
  (and (map? value)
       (contains? value "median")
       (contains? value "sampleSize")))

(defn- product-sort-key
  [product]
  (let [index (.indexOf ^java.util.List product-order product)]
    (if (<= 0 index)
      [0 index ""]
      [1 0 product])))

(defn- monthly-items
  [city]
  (let [figures (get city "figures")
        by-type (get city "byType")]
    (cond
      (seq figures) figures
      (seq by-type) by-type
      :else [])))

(defn- require-product
  [item]
  (let [product (get item "optionType")]
    (when (str/blank? (str product))
      (throw (ex-info "A figure has no optionType." {})))
    product))

(defn- rate-rows
  "SPEC section 3. One row per published city and product. Unpublished cities are omitted."
  [data]
  (let [as-of (get data "asOf")
        rows (mapv
              (fn [row]
                (let [sample (get row :sample_size)]
                  (when-not (number? sample)
                    (throw (ex-info "A rate row has no sampleSize." {:row row})))
                  (assoc row
                         :low_confidence (< sample 10)
                         :as_of as-of)))
              (mapcat
               (fn [city]
                 (let [city-map (get city "city")
                       slug (get city-map "slug")
                       name (get city-map "name")
                       currency (get city "currency")]
                   (when (or (str/blank? (str slug)) (str/blank? (str name)))
                     (throw (ex-info "A city is missing its slug or name." {})))
                   (when (str/blank? (str currency))
                     (throw (ex-info "A published city is missing its currency."
                                     {:city slug})))
                   (let [base {:city_slug slug
                               :city_name name
                               :country_code (get city "countryCode")
                               :currency currency}]
                     (concat
                      (for [item (monthly-items city)]
                        (assoc base
                               :product (require-product item)
                               :unit "month"
                               :median (amount (get item "median"))
                               :p25 (amount (get item "p25"))
                               :p75 (amount (get item "p75"))
                               :sample_size (get item "sampleSize")
                               :property_count (get item "propertyCount")
                               :operator_count (get item "operatorCount")))
                      (for [[key value] city
                            :when (stat? value)
                            :let [product (snake key)]]
                        (assoc base
                               :product product
                               :unit (get stat-units product)
                               :median (amount (get value "median"))
                               :p25 (amount (get value "p25"))
                               :p75 (amount (get value "p75"))
                               :sample_size (get value "sampleSize")
                               :property_count (get value "propertyCount")
                               :operator_count (get value "operatorCount")))))))
               (or (get data "cities") [])))]
    (->> rows
         (sort-by (fn [row] [(:city_slug row) (product-sort-key (:product row))]))
         (mapv #(select-keys % rate-columns)))))

(defn- city-rows
  "SPEC section 4. Published cities first, then unpublished, each by slug."
  [data]
  (let [as-of (get data "asOf")
        published (for [city (or (get data "cities") [])]
                    (let [city-map (get city "city")]
                      {:city_slug (get city-map "slug")
                       :city_name (get city-map "name")
                       :country_code (get city "countryCode")
                       :currency (get city "currency")
                       :published true
                       :property_count (get city "propertyCount")
                       :operator_count (get city "operatorCount")
                       :entry_median (amount (get city "entryMedian"))
                       :entry_min (amount (get city "entryMin"))
                       :entry_max (amount (get city "entryMax"))
                       :p25 (amount (get city "p25"))
                       :p75 (amount (get city "p75"))
                       :sample_size (get city "sampleSize")
                       :as_of as-of}))
        unpublished (for [city (or (get data "unpublished") [])]
                      (let [city-map (get city "city")]
                        {:city_slug (get city-map "slug")
                         :city_name (get city-map "name")
                         :country_code (get city "countryCode")
                         :currency (get city "currency")
                         :published false
                         :property_count nil
                         :operator_count nil
                         :entry_median nil
                         :entry_min nil
                         :entry_max nil
                         :p25 nil
                         :p75 nil
                         :sample_size nil
                         :as_of as-of}))]
    (->> (concat published unpublished)
         (sort-by (fn [row] [(if (:published row) 0 1) (:city_slug row)]))
         (mapv #(select-keys % city-columns)))))

(defn- parse-body
  "Turn a `GET /v1/market/rates` body into rates, cities and the credit fields.

  Throws when the body is not the documented JSON envelope. Amounts are the
  API's own numbers."
  [body]
  (let [parsed (json/read-str body)]
    (when-not (map? parsed)
      (throw (ex-info "The API body is not a JSON object." {})))
    (let [data (get parsed "data")]
      (when-not (map? data)
        (throw (ex-info "The API body has no data object." {})))
      {:rates (rate-rows data)
       :cities (city-rows data)
       :attribution (get data "attribution")
       :license (get data "license")
       :license_url (get data "licenseUrl")
       :as_of (get data "asOf")
       :scope (get data "scope")})))

(defn- same-country?
  [row country]
  (or (nil? country)
      (= (str/lower-case country)
         (some-> (:country_code row) str str/trim str/lower-case))))

(defn- same-currency?
  [row currency]
  (or (nil? currency)
      (= (str/upper-case (str currency))
         (some-> (:currency row) str str/trim str/upper-case))))

(defn- filter-snapshot
  "Keep snapshot rows that already use the requested city, country and currency.

  Currency is compared, not converted. A request for USD does not turn a EUR
  median into a USD median."
  [snapshot {:keys [city country currency]}]
  (let [keep? (fn [row]
                (and (or (nil? city) (core/matches-city? row city))
                     (same-country? row country)
                     (same-currency? row currency)))]
    (assoc snapshot
           :rates (filterv keep? (:rates snapshot))
           :cities (filterv keep? (:cities snapshot)))))

(defn- snapshot-result
  [opts error]
  (let [result (-> (core/snapshot)
                   (filter-snapshot opts)
                   (assoc :origin :snapshot))]
    (if error
      (assoc result :error error)
      result)))

(defn- success?
  [response]
  (let [status (:status response)]
    (and (integer? status) (<= 200 status 299))))

(defn- retryable?
  [response]
  (let [status (:status response)]
    (or (= status 429) (and (integer? status) (<= 500 status 599)))))

(defn- fetch-once
  [http request]
  (http request))

(defn- fetch
  [http sleep request]
  (let [first (fetch-once http request)]
    (if (or (success? first) (not (retryable? first)))
      first
      (do
        (sleep (retry-wait (:headers first)))
        (fetch-once http request)))))

(defn price-index
  "Load the Price Index from `GET /v1/market/rates`.

  Options, all optional:

  - `:base-url` overrides the origin. The default is `COWORKINGVIEW_API_URL`
    or `https://api.coworkingview.com`.
  - `:locale` is `en` (default), `es` or `de`.
  - `:city`, `:country` and `:currency` are the documented query filters.
    `:currency` is `EUR`, `GBP`, `USD`, `CHF`, `AED` or `VES`.
  - `:offline` skips the request and returns the bundled snapshot.
  - `:http` and `:sleep` replace the request and the retry wait. Tests use them.

  A live result has `:origin :api`. Rates and cities are parsed from that
  body. `:license` is the response's licence code and `:license_url` is its
  `licenseUrl`. A failed request, a non-JSON body, or a non-2xx status after
  one retry returns the bundled snapshot with `:origin :snapshot` and
  `:error`. HTTP 429 and 5xx are retried once. The wait is `Retry-After`,
  otherwise `RateLimit-Reset`, otherwise 2 seconds, and never more than 10.
  Other statuses are not retried.

  The snapshot fallback does not convert currency. When `:currency` is set,
  only rows already in that currency are returned. `:attribution` is still
  the CC BY 4.0 credit."
  ([]
   (price-index {}))
  ([{:keys [http sleep offline] :as opts
     :or {http http-get
          sleep default-sleep}}]
   (let [request {:url (endpoint opts)
                  :headers {"Accept" "application/json"
                            "User-Agent" user-agent}}]
     (if offline
       (snapshot-result opts nil)
       (try
         (let [response (fetch http sleep request)]
           (if (success? response)
             (assoc (parse-body (:body response)) :origin :api)
             (snapshot-result opts (str "HTTP " (:status response)))))
         (catch InterruptedException _
           (.interrupt (Thread/currentThread))
           (snapshot-result opts "The request was interrupted."))
         (catch clojure.lang.ExceptionInfo e
           (if (caller-error? e)
             (throw e)
             (snapshot-result opts (or (ex-message e) "The Price Index request failed."))))
         (catch Exception e
           (snapshot-result opts (or (ex-message e) "The Price Index request failed."))))))))

(defn rate
  "The Price Index row for `city` and `product`.

  Uses [[price-index]], so a failed request falls back to the bundled
  snapshot. `opts` are the same options as [[price-index]]. Returns `nil`
  when that index has no such row. A `:currency` the snapshot is not stored
  in yields `nil` on fallback, rather than a converted amount."
  ([city product]
   (rate city product {}))
  ([city product opts]
   (core/rate city product (:rates (price-index opts)))))

(defn cities
  "Cities from [[price-index]], live when the request succeeds, otherwise the snapshot.

  `opts` are the options of [[price-index]]."
  ([]
   (cities {}))
  ([opts]
   (:cities (price-index opts))))

(defn attribution
  "CC BY 4.0 credit from [[price-index]].

  The live response's own attribution when the request succeeds, otherwise
  the credit stored with the snapshot."
  ([]
   (attribution {}))
  ([opts]
   (:attribution (price-index opts))))
