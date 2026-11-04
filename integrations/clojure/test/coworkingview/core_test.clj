(ns coworkingview.core-test
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [coworkingview.core :as core]))

(defn repo-file
  [& parts]
  (let [here (.getCanonicalFile (io/file "."))
        roots [here
               (.getParentFile here)
               (some-> here .getParentFile .getParentFile)]]
    (if-let [root (some (fn [dir]
                          (when (and dir (.isFile (io/file dir "spec/golden/rates.csv")))
                            dir))
                        roots)]
      (apply io/file root parts)
      (throw (ex-info "Cannot find spec/golden/rates.csv from the working directory."
                      {:cwd (str here)})))))

(defn- parse-cell
  [raw]
  (cond
    (= raw "") nil
    (= raw "true") true
    (= raw "false") false
    (re-matches #"-?\d+" raw) (Long/parseLong raw)
    :else raw))

(defn- read-csv
  [file]
  (let [lines (str/split-lines (slurp file))
        header (mapv keyword (str/split (first lines) #","))]
    (mapv (fn [line]
            (let [cells (str/split line #"," -1)]
              (when (not= (count cells) (count header))
                (throw (ex-info "Unexpected CSV width." {:file (str file) :line line})))
              (zipmap header (map parse-cell cells))))
          (rest lines))))

(defn- fixture-data
  []
  (get (json/read-str (slurp (repo-file "spec/fixtures/market_rates.json"))) "data"))

(deftest snapshot-matches-the-open-tables
  (let [rates (read-csv (repo-file "spec/golden/rates.csv"))
        cities (read-csv (repo-file "spec/golden/cities.csv"))
        data (fixture-data)
        bundled (core/snapshot)]
    (is (= rates (:rates bundled)))
    (is (= cities (:cities bundled)))
    (is (= (get data "asOf") (:as_of bundled)))
    (is (= (get data "license") (:license bundled)))
    (is (= (get data "licenseUrl") (:license_url bundled)))
    (is (= (get data "attribution") (:attribution bundled)))
    (is (= (get data "scope") (:scope bundled)))
    (is (str/includes? (:source bundled) "spec/golden/rates.csv"))
    (is (str/includes? (:source bundled) "spec/golden/cities.csv"))))

(deftest attribution-is-the-cc-by-credit
  (let [credit (core/attribution)]
    (is (= (:attribution (core/snapshot)) credit))
    (is (str/includes? credit "CC BY 4.0"))
    (is (str/includes? credit "https://creativecommons.org/licenses/by/4.0/"))
    (is (str/includes? credit "https://coworkingview.com/en/tools/price-index"))))

(deftest rate-reads-the-recorded-berlin-flex-desk
  (let [row (core/rate "berlin" "flex_desk")]
    (is (= "berlin" (:city_slug row)))
    (is (= "Berlin" (:city_name row)))
    (is (= "DE" (:country_code row)))
    (is (= "EUR" (:currency row)))
    (is (= "flex_desk" (:product row)))
    (is (= "month" (:unit row)))
    (is (= 214 (:median row)))
    (is (= 199 (:p25 row)))
    (is (= 292 (:p75 row)))
    (is (= 72 (:sample_size row)))
    (is (false? (:low_confidence row)))
    (is (= "2026-10-27T21:06:48.313Z" (:as_of row)))))

(deftest rate-accepts-display-names-and-separators
  (is (= 214 (:median (core/rate "Berlin" "Flex desk"))))
  (is (= 1400 (:median (core/rate "abu_dhabi" "flex-desk"))))
  (is (= "Abu Dhabi" (:city_name (core/rate "Abu Dhabi" "flex_desk")))))

(deftest rate-keeps-missing-percentiles-nil
  (let [row (core/rate "madrid" "meeting_room")]
    (is (= 28 (:median row)))
    (is (nil? (:p25 row)))
    (is (nil? (:p75 row)))
    (is (= 8 (:sample_size row)))
    (is (true? (:low_confidence row)))
    (is (= "hour" (:unit row)))))

(deftest missing-rows-are-nil
  (is (nil? (core/rate "example-town" "flex_desk")))
  (is (nil? (core/rate "nowhere" "flex_desk")))
  (is (nil? (core/rate "berlin" "event_space")))
  (is (nil? (core/rate "" "flex_desk")))
  (is (nil? (core/rate "berlin" nil))))

(deftest cities-include-the-unpublished-fixture
  (let [rows (core/cities)
        unpublished (last rows)]
    (is (= ["abu-dhabi" "berlin" "madrid" "example-town"]
           (mapv :city_slug rows)))
    (is (= [true true true false] (mapv :published rows)))
    (is (= "Example Town" (:city_name unpublished)))
    (is (false? (:published unpublished)))
    (is (nil? (:country_code unpublished)))
    (is (nil? (:currency unpublished)))
    (is (nil? (:entry_median unpublished)))
    (is (nil? (:sample_size unpublished)))
    (let [berlin (some #(when (core/matches-city? % "berlin") %) rows)]
      (is (= 265 (:entry_median berlin)))
      (is (= 85 (:sample_size berlin)))
      (is (= "EUR" (:currency berlin))))))
