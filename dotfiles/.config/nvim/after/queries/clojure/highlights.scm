;; extends

; ============================================================================
; Solarized Dark Architecture: Clojure (Tier 4 Functional)
; ============================================================================

; (ns core.telemetry.collector (:require ...) (:import ...)) in Solarized Violet (#6C71C4)
(list_lit
  .
  (sym_lit) @keyword.import
  (#eq? @keyword.import "ns")
  .
  (sym_lit) @module
  (#set! priority 125))

(list_lit
  .
  (kwd_lit) @keyword.import
  (#any-of? @keyword.import ":require" ":import" ":use" ":refer-clojure")
  (#set! priority 125))

; Metadata (^:private, ^String, ^double, ^long) unified in Solarized Violet (#6C71C4)
((meta_lit) @attribute
  (#set! priority 125))

(meta_lit
  "^" @attribute
  (#set! priority 125))

(meta_lit
  (kwd_lit) @attribute
  (#set! priority 125))

(meta_lit
  (sym_lit) @attribute
  (#set! priority 125))

(meta_lit
  (sym_lit
    (sym_name) @attribute)
  (#set! priority 125))

; Reader macro quote/unquote/deref operators in calm Base0 (#839496)
(syn_quoting_lit
  "`" @operator
  (#set! priority 120))

(quoting_lit
  "'" @operator
  (#set! priority 120))

(unquoting_lit
  "~" @operator
  (#set! priority 120))

(unquote_splicing_lit
  "~@" @operator
  (#set! priority 120))

(derefing_lit
  "@" @operator
  (#set! priority 120))

; Structural definition & binding forms in Solarized Green (#859900)
(list_lit
  .
  (sym_lit) @keyword.function
  (#any-of? @keyword.function
    "defn" "defn-" "defmacro" "defmulti" "defmethod" "fn" "fn*")
  (#set! priority 120))

(list_lit
  .
  (sym_lit) @keyword
  (#any-of? @keyword
    "def" "defonce" "defprotocol" "defrecord" "deftype" "defstruct"
    "let" "let*" "letfn" "loop" "do" "binding" "with-open"
    "extend-type" "extend-protocol" "reify" "and" "or" "not")
  (#set! priority 120))

; Declared function, macro, and protocol method names in Solarized Blue (#268BD2)
(list_lit
  .
  (sym_lit) @_def_kw
  (#any-of? @_def_kw "defn" "defn-" "defmacro" "defmulti" "defmethod")
  .
  (sym_lit
    name: (sym_name) @function)
  (#set! priority 120))

; Protocol method declarations inside (defprotocol Name (method [this] ...))
(list_lit
  .
  (sym_lit) @_proto_kw
  (#eq? @_proto_kw "defprotocol")
  .
  (sym_lit) @type
  (list_lit
    .
    (sym_lit
      name: (sym_name) @function))
  (#set! priority 120))

; Record / type declarations (defrecord MetricSample [...] Protocol (method [...] ...))
(list_lit
  .
  (sym_lit) @_rec_kw
  (#any-of? @_rec_kw "defrecord" "deftype")
  .
  (sym_lit) @type
  (#set! priority 120))

; Control flow forms in Solarized Yellow (#B58900)
(list_lit
  .
  (sym_lit) @keyword.conditional
  (#any-of? @keyword.conditional
    "if" "if-not" "if-let" "if-some"
    "when" "when-not" "when-let" "when-some" "when-first"
    "cond" "condp" "cond->" "cond->>" "case")
  (#set! priority 120))

(list_lit
  .
  (sym_lit) @keyword.repeat
  (#any-of? @keyword.repeat "recur" "for" "doseq" "dotimes" "while")
  (#set! priority 120))

(list_lit
  .
  (sym_lit) @keyword.exception
  (#any-of? @keyword.exception "try" "catch" "finally" "throw")
  (#set! priority 120))

; Neutralize upstream @function.macro / @function.method (Blue) on threading macros
; and Java static/instance interop calls so they remain in calm Base0 (#839496)
(list_lit
  .
  (sym_lit) @function.call
  (#any-of? @function.call "->" "->>" "some->" "some->>" "as->" "doto" "..")
  (#set! priority 120))

((sym_lit
  name: (sym_name) @_name) @function.call
  (#lua-match? @_name "^%.[^-]")
  (#set! priority 125))

(list_lit
  .
  (sym_lit
    namespace: (sym_ns) @_namespace
    (#lua-match? @_namespace "^%u")) @function.call
  (#set! priority 125))

; Keywords (:keyword, :namespaced/keyword), nil, booleans, numbers, and regexes in Solarized Magenta (#D33682)
((kwd_lit) @string.special.symbol
  (#set! priority 115))

((nil_lit) @constant.builtin
  (#set! priority 115))

((bool_lit) @boolean
  (#set! priority 115))

((num_lit) @number
  (#set! priority 115))

((regex_lit) @string.regexp
  (#set! priority 115))

(regex_lit
  "#" @string.regexp
  (#set! priority 120))
