;; extends

; Option A: Map package keyword to @keyword (Solarized Green #859900)
; import keyword remains @keyword.import linking to Include (Solarized Orange #cb4b16)
"package" @keyword

; In Go, factory functions like NewClusterNode are regular functions, not constructors.
; Keep function invocations consistently Blue (@function.call #268bd2) matching definition.
((call_expression
  (identifier) @function.call)
  (#lua-match? @function.call "^[nN]ew.+$"))

((call_expression
  (identifier) @function.call)
  (#lua-match? @function.call "^[mM]ake.+$"))
