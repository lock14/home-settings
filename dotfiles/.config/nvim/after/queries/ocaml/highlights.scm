;; extends

; ============================================================================
; Solarized Dark Architecture: OCaml (Tier 4 Functional)
; ============================================================================

; Import directives (open, include) and formal module / module type names in Solarized Violet (#6C71C4)
[
  "open"
  "include"
] @keyword.import
(#set! priority 120)

[
  (module_name)
  (module_type_name)
] @module
(#set! priority 115)

; In-code qualified module references (List.fold_left, Printf.sprintf) in calm Base0 (#839496)
(value_path
  (module_path
    (module_name) @type)
  (value_name) @function.call
  (#set! priority 125))

; Structural module & binding keywords in Solarized Green (#859900)
[
  "module"
  "struct"
  "sig"
  "end"
  "functor"
  "type"
  "let"
  "rec"
  "and"
  "in"
  "val"
  "mutable"
  "external"
  "fun"
  "of"
  "as"
  "exception"
  "nonrec"
  "private"
  "virtual"
  "object"
  "class"
  "method"
  "inherit"
  "initializer"
  "constraint"
  "lazy"
  "assert"
  "begin"
  "new"
] @keyword
(#set! priority 120)

; Control flow keywords (match, with, when, if, then, else, for, while, try, function) in Solarized Yellow (#B58900)
[
  "match"
  "with"
  "when"
  "if"
  "then"
  "else"
  "function"
] @keyword.conditional
(#set! priority 120)

[
  "for"
  "to"
  "downto"
  "while"
  "do"
  "done"
] @keyword.repeat
(#set! priority 120)

"try" @keyword.exception
(#set! priority 120)

((value_name) @keyword.exception
  (#any-of? @keyword.exception "raise" "raise_notrace")
  (#set! priority 120))

; Type variables ('a, 'b) in Solarized Green (#859900)
(type_variable) @keyword.modifier
(#set! priority 120)

; Scalar primitive types in Solarized Green (#859900), overriding upstream's inverted (type_constructor) @type fallback
((type_constructor) @type.builtin
  (#any-of? @type.builtin
    "int" "int32" "int64" "nativeint"
    "float" "bool" "string" "bytes" "char" "unit")
  (#set! priority 120))

; Container and custom types (list, option, array, result, sample, severity) in calm Base0 (#839496)
((type_constructor) @type
  (#any-of? @type "list" "option" "array" "result" "exn" "lazy_t" "format4" "format6")
  (#set! priority 120))

; Function declarations in val specifications (val clamp_score : ...) in Solarized Blue (#268BD2)
(value_specification
  (value_name) @function
  (#set! priority 120))

; Polymorphic variants (`Active, `Draining), None sentinel, booleans, and () unit in Solarized Magenta (#D33682)
(tag) @constant
(#set! priority 120)

((constructor_name) @constant.builtin
  (#eq? @constant.builtin "None")
  (#set! priority 120))

(unit) @constant.builtin
(#set! priority 120)

(boolean) @boolean
(#set! priority 120)
