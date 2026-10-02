;; extends

; ============================================================================
; Solarized Dark Architecture: Elixir (Tier 4 Functional)
; ============================================================================

; Neutralize upstream's blanket @constant / @comment.documentation captures on
; the entire (unary_operator operator: "@") and operand: (call) subtree.
(unary_operator
  operator: "@"
  operand: (call) @variable
  (#set! priority 105)) @variable

(unary_operator
  operator: "@"
  operand: (identifier) @variable
  (#set! priority 105)) @variable

; Re-assert core leaf tokens above the neutralized @attribute subtree (priority 108-120)
((identifier) @variable
  (#set! priority 108))

((string) @string
  (#set! priority 110))

((quoted_content) @string
  (#set! priority 110))

((escape_sequence) @string.escape
  (#set! priority 115))

; String interpolation: #{...} delimiters and inner expressions in calm Base0 (#839496)
((interpolation) @variable
  (#set! priority 112))

(interpolation
  "#{" @punctuation.special
  "}" @punctuation.special
  (#set! priority 120))

(interpolation
  (identifier) @variable
  (#set! priority 115))

(interpolation
  (call
    target: (identifier) @function.call)
  (#set! priority 115))

; Atoms, keyword keys (key:), booleans, nil, numbers, and special module constants in Solarized Magenta (#D33682)
((atom) @string.special.symbol
  (#set! priority 115))

((keyword) @string.special.symbol
  (#set! priority 115))

((boolean) @boolean
  (#set! priority 115))

((nil) @constant.builtin
  (#set! priority 115))

((integer) @number
  (#set! priority 115))

((float) @number.float
  (#set! priority 115))

((identifier) @constant.builtin
  (#any-of? @constant.builtin "__MODULE__" "__DIR__" "__ENV__" "__CALLER__" "__STACKTRACE__")
  (#set! priority 120))

; In-code module qualifiers and struct names (Enum, String, Map, GenServer, %MetricSample{}) in calm Base0 (#839496)
((alias) @type
  (#set! priority 115))

; Function calls (including piped function calls) in calm Base0 (#839496)
(call
  target: (identifier) @function.call
  (#set! priority 112))

(call
  target: (dot
    right: (identifier) @function.call)
  (#set! priority 115))

(binary_operator
  operator: "|>"
  right: (identifier) @function.call
  (#set! priority 115))

; Anonymous function capture placeholders (&1, &2) in calm Base0 (#839496)
(unary_operator
  operator: "&" @operator
  operand: (integer) @operator
  (#set! priority 120))

((operator_identifier) @operator
  (#set! priority 115))

([
  "::"
  "|"
  "->"
  "<-"
  "\\\\"
  "|>"
  "="
  "=="
  "!="
  "==="
  "!=="
  "<"
  ">"
  "<="
  ">="
  "+"
  "-"
  "*"
  "/"
  "++"
  "--"
  "<>"
  "&&"
  "||"
  "!"
  "&"
  "%"
] @operator
  (#set! priority 115))

([
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "<<"
  ">>"
] @punctuation.bracket
  (#set! priority 115))

([
  ","
  ";"
  "."
] @punctuation.delimiter
  (#set! priority 115))

; Unified module attributes (@moduledoc, @doc, @spec, @type, @impl, @default_timeout) in Solarized Violet (#6C71C4)
(unary_operator
  operator: "@" @attribute
  operand: [
    (identifier) @attribute
    (call
      target: (identifier) @attribute)
  ]
  (#set! priority 125))

; Formal module declarations (defmodule Core.Telemetry.Collector) in Solarized Green + Violet
(call
  target: (identifier) @keyword.function
  (arguments
    (alias) @module)
  (#any-of? @keyword.function "defmodule" "defprotocol")
  (#set! priority 125))

; Import/use/alias/require directives and target module names in Solarized Violet (#6C71C4)
(call
  target: (identifier) @keyword.import
  (arguments
    [
      (alias) @module
      (dot
        left: (alias) @module)
    ])
  (#any-of? @keyword.import "use" "import" "alias" "require")
  (#set! priority 125))

; Structural definition macros (defstruct, defimpl, defexception, defoverridable) in Solarized Green (#859900)
(call
  target: (identifier) @keyword.function
  (#any-of? @keyword.function "defstruct" "defimpl" "defexception" "defoverridable")
  (#set! priority 125))

; Function / macro / guard declarations (def, defp, defmacro, defguard) in Solarized Green + Blue (#268BD2)
(call
  target: (identifier) @keyword.function
  (arguments
    [
      (identifier) @function
      (call
        target: (identifier) @function)
      (binary_operator
        left: (call
          target: (identifier) @function)
        operator: "when")
    ])
  (#any-of? @keyword.function "def" "defp" "defmacro" "defmacrop" "defguard" "defguardp" "defdelegate")
  (#set! priority 125))

; Control flow macros & keywords in Solarized Yellow (#B58900)
(call
  target: (identifier) @keyword.conditional
  (#any-of? @keyword.conditional "case" "cond" "with" "if" "unless" "receive")
  (#set! priority 125))

(call
  target: (identifier) @keyword.repeat
  (#any-of? @keyword.repeat "for")
  (#set! priority 125))

(call
  target: (identifier) @keyword.exception
  (#any-of? @keyword.exception "try" "raise" "throw" "reraise")
  (#set! priority 125))

([
  "when"
  "else"
] @keyword.conditional
  (#set! priority 125))

([
  "rescue"
  "catch"
  "after"
] @keyword.exception
  (#set! priority 125))

; Structural block & word operator keywords in Solarized Green (#859900)
([
  "do"
  "end"
  "fn"
] @keyword
  (#set! priority 125))

([
  "and"
  "or"
  "not"
  "in"
] @keyword.operator
  (#set! priority 125))
