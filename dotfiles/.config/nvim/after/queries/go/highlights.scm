;; extends

; Map package keyword to @keyword (Solarized Green #859900)
"package" @keyword

; Map import keyword to @keyword.import (Solarized Violet #6c71c4)
"import" @keyword.import

; Module declarations (e.g. package main) are Solarized Violet (@module #6c71c4)
(package_clause
  (package_identifier) @module)

; Blank identifier _ is a sentinel / anonymous identifier (Solarized Magenta #d33682)
(blank_identifier) @constant.builtin

; Package qualifiers in qualified types (e.g. context.Context, time.Duration, sync.RWMutex)
; remain calm in neutral Base0 grey (@variable) matching function body qualifiers (fmt.Sprintf).
(qualified_type
  package: (package_identifier) @variable)

; In Go, factory functions like NewClusterNode are regular functions, not constructors.
; Invocations remain in Base0 (@function.call #839496) under the converged scheme.
((call_expression
  (identifier) @function.call)
  (#lua-match? @function.call "^[nN]ew.+$"))

((call_expression
  (identifier) @function.call)
  (#lua-match? @function.call "^[mM]ake.+$"))

; Control flow and jumps in Solarized Yellow (#b58900)
[
  "defer"
  "select"
  "case"
  "default"
  "if"
  "else"
  "switch"
  "break"
  "continue"
  "goto"
  "fallthrough"
] @keyword.conditional

; Built-in function invocations remain in calm Base0 Grey (@function.call #839496)
((call_expression
  (identifier) @function.call)
  (#any-of? @function.call
    "append" "cap" "clear" "close" "complex" "copy" "delete" "imag" "len" "make" "max" "min" "new"
    "panic" "print" "println" "real" "recover"))

; Blank identifier _ in assignments or parameters (Solarized Magenta #d33682)
((identifier) @constant.builtin
  (#eq? @constant.builtin "_"))
