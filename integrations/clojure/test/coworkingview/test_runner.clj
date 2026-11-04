(ns coworkingview.test-runner
  (:require [clojure.test :as test]
            coworkingview.core-test
            coworkingview.client-test))

(defn -main
  [& _]
  (let [{:keys [fail error]} (apply test/run-tests
                                    '[coworkingview.core-test
                                      coworkingview.client-test])]
    (shutdown-agents)
    (System/exit (if (zero? (+ fail error)) 0 1))))
