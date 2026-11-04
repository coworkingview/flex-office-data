(ns coworkingview.client-test
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [coworkingview.client :as client]
            [coworkingview.core :as core]
            [coworkingview.core-test :as fixtures]))

(defn- fixture-body
  []
  (slurp (fixtures/repo-file "spec/fixtures/market_rates.json")))

(defn- scripted
  "An :http double. Each response is a map or an exception to throw."
  [responses]
  (let [calls (atom [])]
    {:calls calls
     :http (fn [request]
             (swap! calls conj request)
             (let [response (nth responses (dec (count @calls)))]
               (if (instance? Throwable response)
                 (throw response)
                 response)))}))

(defn- ok
  [body]
  {:status 200 :body body :headers {}})

(deftest live-body-matches-the-bundled-snapshot
  (let [{:keys [http calls]} (scripted [(ok (fixture-body))])
        loaded (client/price-index {:http http :sleep (fn [_] (throw (ex-info "no retry" {})))})]
    (is (= 1 (count @calls)))
    (is (= :api (:origin loaded)))
    (is (nil? (:error loaded)))
    (is (= (:rates (core/snapshot)) (:rates loaded)))
    (is (= (:cities (core/snapshot)) (:cities loaded)))
    (is (= (:attribution (core/snapshot)) (:attribution loaded)))
    (is (= "CC-BY-4.0" (:license loaded)))
    (is (= "https://creativecommons.org/licenses/by/4.0/" (:license_url loaded)))
    (is (= "2026-10-27T21:06:48.313Z" (:as_of loaded)))
    (is (str/includes? (:url (first @calls)) "https://api.coworkingview.com/v1/market/rates?"))
    (is (str/includes? (:url (first @calls)) "locale=en"))
    (is (= client/user-agent (get-in (first @calls) [:headers "User-Agent"])))
    (is (= "application/json" (get-in (first @calls) [:headers "Accept"])))))

(deftest by-type-fallback-uses-the-recorded-abu-dhabi-figures
  (let [envelope (json/read-str (fixture-body))
        data (get envelope "data")
        cities (mapv (fn [city]
                       (if (= "abu-dhabi" (get-in city ["city" "slug"]))
                         (assoc city "figures" [])
                         city))
                     (get data "cities"))
        body (json/write-str (assoc envelope "data" (assoc data "cities" cities)))
        {:keys [http]} (scripted [(ok body)])
        loaded (client/price-index {:http http :sleep (fn [_])})
        abu (filterv #(= "abu-dhabi" (:city_slug %)) (:rates loaded))]
    (is (= [["flex_desk" 1400 nil true]
            ["fix_desk" 1800 nil true]
            ["private_office" 2057 nil true]]
           (mapv (fn [row] [(:product row) (:median row) (:p25 row) (:low_confidence row)]) abu)))
    (is (= "month" (:unit (first abu))))
    (is (nil? (:property_count (first abu))))))

(deftest future-aggregate-keys-follow-the-spec
  ;; Same shape as python/tests/test_parse.py. These inputs are a parser case,
  ;; not Price Index figures, and they are not part of the bundled snapshot.
  (let [money (fn [amount] {"amount" amount "currency" "CHF"})
        stat (fn [median n extra]
               (merge {"median" (money median) "sampleSize" n} extra))
        body (json/write-str
              {"data" {"asOf" "2026-10-27T00:00:00Z"
                       "attribution" "parser-case"
                       "cities" [{"city" {"slug" "zurich" "name" "Zurich"}
                                  "currency" "CHF"
                                  "figures" []
                                  "byType" [(assoc (stat 900 12 {}) "optionType" "private_office")
                                            (assoc (stat 400 4 {}) "optionType" "flex_desk")]
                                  "eventSpace" (stat 150 3 {"p25" (money 100) "p75" (money 200)})
                                  "virtualOffice" (stat 60 20 {})
                                  "parkingSpot" (stat 120 5 {})
                                  "aRooftop" (stat 10 1 {})
                                  "p25" (money 1)
                                  "insufficientData" false}]
                       "unpublished" [{"city" {"slug" "bern" "name" "Bern"}}]}})
        {:keys [http]} (scripted [(ok body)])
        loaded (client/price-index {:http http :sleep (fn [_])})
        rows (:rates loaded)]
    (is (= [["flex_desk" "month" 400 nil true]
            ["private_office" "month" 900 nil false]
            ["event_space" "hour" 150 100 true]
            ["virtual_office" "month" 60 nil false]
            ["a_rooftop" nil 10 nil true]
            ["parking_spot" nil 120 nil true]]
           (mapv (fn [row]
                   [(:product row) (:unit row) (:median row) (:p25 row) (:low_confidence row)])
                 rows)))
    (is (= #{"zurich"} (set (map :city_slug rows))))
    (is (nil? (:country_code (first rows))))
    (is (nil? (:property_count (first rows))))
    (is (= ["zurich" "bern"] (mapv :city_slug (:cities loaded))))
    (is (= [true false] (mapv :published (:cities loaded))))
    (is (nil? (:currency (second (:cities loaded)))))))

(deftest failure-falls-back-to-the-snapshot
  (testing "connection failure"
    (let [{:keys [http calls]} (scripted [(ex-info "connection refused" {})])
          loaded (client/price-index {:http http :sleep (fn [_])})
          lookup (scripted [(ex-info "connection refused" {})])]
      (is (= 1 (count @calls)))
      (is (= :snapshot (:origin loaded)))
      (is (= (:rates (core/snapshot)) (:rates loaded)))
      (is (= 214 (:median (client/rate "berlin" "flex_desk" {:http (:http lookup) :sleep (fn [_])}))))
      (is (str/includes? (:error loaded) "connection refused"))))
  (testing "non-JSON success body"
    (let [{:keys [http]} (scripted [(ok "not-json")])
          loaded (client/price-index {:http http :sleep (fn [_])})]
      (is (= :snapshot (:origin loaded)))
      (is (= (:attribution (core/snapshot)) (:attribution loaded)))))
  (testing "404 is not retried"
    (let [{:keys [http calls]} (scripted [{:status 404 :body "{\"title\":\"no\"}" :headers {}}])
          loaded (client/price-index {:http http :sleep (fn [_] (throw (ex-info "slept" {})))})]
      (is (= 1 (count @calls)))
      (is (= :snapshot (:origin loaded)))
      (is (= "HTTP 404" (:error loaded)))))
  (testing "500 then 500"
    (let [{:keys [http calls]} (scripted [{:status 500 :body "" :headers {}}
                                          {:status 503 :body "" :headers {}}])
          loaded (client/price-index {:http http :sleep (fn [_])})]
      (is (= 2 (count @calls)))
      (is (= :snapshot (:origin loaded)))
      (is (= "HTTP 503" (:error loaded)))))
  (testing "500 then the recorded body"
    (let [{:keys [http calls]} (scripted [{:status 500 :body "" :headers {"Retry-After" "120"}}
                                          (ok (fixture-body))])
          slept (atom nil)
          loaded (client/price-index {:http http
                                      :sleep (fn [seconds] (reset! slept seconds))})]
      (is (= 2 (count @calls)))
      (is (= 10.0 @slept))
      (is (= :api (:origin loaded)))
      (is (= 214 (:median (some #(when (and (= "berlin" (:city_slug %))
                                            (= "flex_desk" (:product %)))
                                   %)
                                (:rates loaded))))))))

(deftest retry-wait-uses-the-documented-headers
  (doseq [[headers expected] [[{"Retry-After" "3"} 3.0]
                              [{"Retry-After" "0"} 0.0]
                              [{"RateLimit-Reset" "4"} 4.0]
                              [{} 2.0]
                              [{"Retry-After" "soon"} 2.0]
                              [{"Retry-After" "Wed, 21 Oct 2015 07:28:00 GMT"} 0.0]]]
    (let [seen (atom nil)
          {:keys [http]} (scripted [{:status 429 :body "{}" :headers headers}
                                    (ok (fixture-body))])]
      (client/price-index {:http http :sleep (fn [seconds] (reset! seen seconds))})
      (is (= expected @seen) (str headers)))))

(defn- always-fail
  []
  (fn [_request]
    (throw (ex-info "offline" {}))))

(deftest currency-fallback-does-not-convert
  (is (nil? (client/rate "berlin" "flex_desk"
                         {:http (always-fail) :currency "USD" :sleep (fn [_])})))
  (is (= 214 (:median (client/rate "berlin" "flex_desk"
                                   {:http (always-fail) :currency "eur" :sleep (fn [_])}))))
  (let [loaded (client/price-index {:http (always-fail) :currency "USD" :sleep (fn [_])})]
    (is (= :snapshot (:origin loaded)))
    (is (empty? (:rates loaded)))
    (is (str/includes? (:attribution loaded) "CC BY 4.0"))))

(deftest offline-skips-the-request
  (let [{:keys [http calls]} (scripted [(ex-info "should not be called" {})])
        loaded (client/price-index {:offline true :http http})]
    (is (empty? @calls))
    (is (= :snapshot (:origin loaded)))
    (is (nil? (:error loaded)))
    (is (= (:cities (core/snapshot)) (client/cities {:offline true})))
    (is (= (core/attribution) (client/attribution {:offline true})))))

(deftest bad-arguments-are-not-a-fallback
  (let [{:keys [http calls]} (scripted [(ok (fixture-body))])]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"locale"
                          (client/price-index {:locale "fr" :http http})))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"currency"
                          (client/rate "berlin" "flex_desk" {:currency "XXX" :http http})))
    (is (empty? @calls))))

(deftest filters-are-sent-on-the-query-string
  (let [{:keys [http calls]} (scripted [(ok (fixture-body))])
        loaded (client/price-index {:http http
                                    :sleep (fn [_])
                                    :base-url "https://example.test/"
                                    :locale "de"
                                    :city "berlin"
                                    :country "DE"
                                    :currency "EUR"})]
    (is (= :api (:origin loaded)))
    (is (= "https://example.test/v1/market/rates?locale=de&city=berlin&country=DE&currency=EUR"
           (:url (first @calls))))))

(deftest base-url-can-come-from-the-environment
  (let [seen (atom nil)]
    (with-redefs [coworkingview.client/env (fn [name]
                                              (when (= name "COWORKINGVIEW_API_URL")
                                                "https://internal.example/api/"))]
      (client/price-index {:http (fn [request]
                                   (reset! seen (:url request))
                                   (ok (fixture-body)))
                           :sleep (fn [_])}))
    (is (str/starts-with? @seen "https://internal.example/api/v1/market/rates?"))))
