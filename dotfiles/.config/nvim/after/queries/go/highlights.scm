;; extends

; Option A: Map package keyword to @keyword (Solarized Green #859900)
; import keyword remains @keyword.import linking to Include (Solarized Orange #cb4b16)
"package" @keyword

; Module declarations (e.g. package main) are Solarized Violet (@module #6c71c4)
(package_clause
  (package_identifier) @module)

; Package qualifiers in qualified types (e.g. context.Context, time.Duration, sync.RWMutex)
; remain calm in neutral Base0 grey (@variable) matching function body qualifiers (fmt.Sprintf).
(qualified_type
  package: (package_identifier) @variable)

; In Go, factory functions like NewClusterNode are regular functions, not constructors.
; Keep function invocations consistently Blue (@function.call #268bd2) matching definition.
((call_expression
  (identifier) @function.call)
  (#lua-match? @function.call "^[nN]ew.+$"))

((call_expression
  (identifier) @function.call)
  (#lua-match? @function.call "^[mM]ake.+$"))
