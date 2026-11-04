(ns coworkingview.core
  "Offline snapshot of the CoworkingView Price Index.

  Figures live in the resource `coworkingview/price-index.edn`, copied from
  spec/golden/rates.csv and spec/golden/cities.csv. The index is CC BY 4.0.
  Keep [[attribution]] with any figure you republish. Loading this namespace
  does not call the network."
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str])
  (:import [java.io PushbackReader]))

(set! *warn-on-reflection* true)

(def ^:private separators #"[\s_-]+")

(defn- read-snapshot
  []
  (let [resource (io/resource "coworkingview/price-index.edn")]
    (when (nil? resource)
      (throw (ex-info "The bundled Price Index snapshot is missing." {})))
    (with-open [reader (io/reader resource)]
      (binding [*read-eval* false]
        (edn/read (PushbackReader. reader))))))

(def ^:private snapshot-delay
  (delay (read-snapshot)))

(defn- blank->nil
  ^String [^String value]
  (when (and (some? value) (not (str/blank? value)))
    value))

(defn- normalize-city
  "Lower-case city text. Spaces, hyphens and underscores are one separator."
  [value]
  (when (some? value)
    (blank->nil (-> (str value) str/trim str/lower-case (str/replace separators " ")))))

(defn- normalize-product
  "Lower-case product text. Spaces, hyphens and underscores become underscores."
  [value]
  (when (some? value)
    (blank->nil (-> (str value) str/trim str/lower-case (str/replace separators "_")))))

(defn snapshot
  "The bundled Price Index capture.

  Keys: `:as_of`, `:license` (`CC-BY-4.0`), `:license_url`, `:attribution`,
  `:scope`, `:source`, `:rates` and `:cities`. Row keys are the open-table
  column names. Empty cells are `nil`. This reads a resource and does not
  call the network."
  []
  @snapshot-delay)

(defn attribution
  "The CC BY 4.0 credit string from the recorded Price Index response.

  The text is copied unchanged. Keep it with any figure you republish."
  []
  (:attribution (snapshot)))

(defn cities
  "Cities in the snapshot, in the recorded order.

  Each map uses the columns of the open cities table, including `:published`.
  The unpublished fixture row `example-town` is included and its price fields
  are `nil`. Entry prices are Price Index figures, so keep [[attribution]]
  with them."
  []
  (:cities (snapshot)))

(defn matches-city?
  "Whether `row` is the city named by `city`.

  `city` is a slug (`berlin`) or a display name (`Abu Dhabi`). Comparison
  ignores case and treats spaces, hyphens and underscores as the same
  separator. A blank `city` matches nothing."
  [row city]
  (let [key (normalize-city city)]
    (boolean (and key
                  (or (= key (normalize-city (:city_slug row)))
                      (= key (normalize-city (:city_name row))))))))

(defn rate
  "The Price Index row for `city` and `product`, or `nil` when it is absent.

  `city` is a slug (`berlin`) or a display name (`Abu Dhabi`). Comparison
  ignores case and treats spaces, hyphens and underscores as the same
  separator. `product` is a product code: `flex_desk`, `fix_desk`,
  `private_office`, `day_pass` or `meeting_room`. The same separator rule
  applies, so `flex desk` matches `flex_desk`.

  The map uses the columns of the open rates table. `:median` is the
  published median. `:p25` and `:p75` are `nil` when the index did not
  publish them. The optional third argument searches `rows` instead of the
  bundled snapshot. Keep [[attribution]] with any figure you republish."
  ([city product]
   (rate city product (:rates (snapshot))))
  ([city product rows]
   (let [product-key (normalize-product product)]
     (when product-key
       (some (fn [row]
               (when (and (matches-city? row city)
                          (= product-key (normalize-product (:product row))))
                 row))
             rows)))))
