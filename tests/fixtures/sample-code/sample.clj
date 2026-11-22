;; ============================================================================
;; Solarized Dark Showcase: Clojure (Clojure 1.12 Immutable Data & Protocols)
;; ============================================================================

(ns core.telemetry.collector
  (:require [clojure.string :as str])
  (:import (java.time Instant)))

(defonce ^:private default-window-ms 5000)
(def max-score-limit 100.0)
(def node-id-pattern #"^node-[a-z0-9-]+$")

(defprotocol Measurable
  (sample-score [this] "Extracts the normalized numeric score.")
  (healthy? [this] "Returns true when the sample is within threshold."))

(defrecord MetricSample [^String node-id ^double score ^long count active?]
  Measurable
  (sample-score [_]
    (min max-score-limit (max 0.0 score)))
  (healthy? [this]
    (and (true? active?) (< (sample-score this) 85.0))))

(defmacro with-telemetry-span
  [span-name & body]
  `(let [started# (System/currentTimeMillis)]
     (try
       ~@body
       (finally
         (let [elapsed# (- (System/currentTimeMillis) started#)]
           {:span ~span-name :elapsed-ms elapsed#})))))

(defn- ^String normalize-node-id
  [raw-id]
  (let [trimmed (str/trim (or raw-id ""))]
    (if (re-matches node-id-pattern trimmed)
      trimmed
      "node-unknown-00")))

(defn classify-sample
  "Classifies a MetricSample into a severity keyword."
  [sample]
  (when-let [score (and sample (sample-score sample))]
    (cond
      (not (:active? sample)) :telemetry/offline
      (>= score 95.0)         :telemetry/fatal
      (>= score 80.0)         :telemetry/critical
      (>= score 60.0)         :telemetry/warn
      :else                   :telemetry/info)))

(defn summarize-batch
  [samples]
  (loop [remaining samples
         acc       {:count 0 :total 0.0 :critical 0 :status :ready}]
    (if (empty? remaining)
      (if (pos? (:count acc))
        (assoc acc :mean (/ (:total acc) (:count acc)))
        (assoc acc :status :empty :mean nil))
      (let [item     (first remaining)
            severity (classify-sample item)
            score    (if (healthy? item) (sample-score item) 0.0)
            crit-inc (case severity
                       :telemetry/critical 1
                       :telemetry/fatal    1
                       0)]
        (recur (rest remaining)
               (-> acc
                   (update :count inc)
                   (update :total + score)
                   (update :critical + crit-inc)))))))
