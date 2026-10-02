;; extends

; Ensure Starlark `load(...)` stays @keyword.import (Solarized Violet #6C71C4)
; instead of being overwritten by the trailing `(call function: (identifier) @function.call)` rule.
((call
  function: (identifier) @keyword.import)
  (#eq? @keyword.import "load")
  (#set! priority 115))

; Starlark has no static type annotations; neutralize Python's @type.builtin
; capture on built-in constructors/identifiers (bool, int, float, list, tuple,
; range, str, bytes, set, dict, type) and Python 2's `print` keyword so they
; remain calm Base0 Grey (#839496) across calls, attributes, and parameters.
((identifier) @variable
  (#any-of? @variable
    "bool" "int" "float" "list" "tuple" "range" "str" "bytes" "set" "dict" "type")
  (#set! priority 105))

("print" @function.builtin
  (#set! priority 105))

; Allow leading `#` comments before module or function docstrings
(module
  .
  (comment)*
  .
  (expression_statement
    (string) @string.documentation))

(function_definition
  body: (block
    .
    (comment)*
    .
    (expression_statement
      (string) @string.documentation)))
