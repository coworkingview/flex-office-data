(ns build
  "Build and deploy net.clojars.coworkingview/coworkingview."
  (:require [clojure.tools.build.api :as b]
            [deps-deploy.deps-deploy :as dd]))

(def lib 'net.clojars.coworkingview/coworkingview)
(def version "0.1.0")
(def class-dir "target/classes")
(def jar-file (format "target/%s-%s.jar" (name lib) version))

(def scm
  {:url "https://github.com/coworkingview/flex-office-data"
   :connection "scm:git:https://github.com/coworkingview/flex-office-data.git"
   :developerConnection "scm:git:ssh://git@github.com/coworkingview/flex-office-data.git"
   :tag "HEAD"})

(def pom-data
  [[:description "Look up flexible-office price medians by city from a bundled CoworkingView Price Index snapshot."]
   [:url "https://coworkingview.com/en/tools/price-index"]
   [:licenses
    [:license
     [:name "MIT License"]
     [:url "https://opensource.org/licenses/MIT"]
     [:distribution "repo"]]]
   [:developers
    [:developer
     [:id "coworkingview"]
     [:name "CoworkingView"]
     [:email "info@coworkingview.com"]
     [:url "https://coworkingview.com"]
     [:organization "CoworkingView"]
     [:organizationUrl "https://coworkingview.com"]]]
   [:organization
    [:name "CoworkingView"]
    [:url "https://coworkingview.com"]]])

(defn- basis
  []
  (b/create-basis {:project "deps.edn"}))

(defn clean
  "Delete target/."
  [_]
  (b/delete {:path "target"}))

(defn pom
  "Write the Maven pom into target/classes."
  [_]
  (b/write-pom {:class-dir class-dir
                :lib lib
                :version version
                :basis (basis)
                :src-dirs ["src"]
                :resource-dirs ["resources"]
                :scm scm
                :pom-data pom-data}))

(defn jar
  "Build target/coworkingview-0.1.0.jar, including the generated pom."
  [_]
  (clean nil)
  (pom nil)
  (b/copy-dir {:src-dirs ["src" "resources"]
               :target-dir class-dir})
  (b/jar {:class-dir class-dir
          :jar-file jar-file}))

(defn deploy
  "Deploy the jar to Clojars.

  deps-deploy reads CLOJARS_USERNAME and CLOJARS_PASSWORD. The password is a
  Clojars deploy token. This task does not create a git tag."
  [_]
  (dd/deploy {:installer :remote
              :artifact jar-file
              :pom-file (b/pom-path {:lib lib :class-dir class-dir})
              :sign-releases? false}))
