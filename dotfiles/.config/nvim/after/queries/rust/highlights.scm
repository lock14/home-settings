;; extends

;; Unify Rust attributes (#[inline], #[derive(...)]) as Solarized Violet (@attribute #6c71c4)
(attribute
  (identifier) @attribute)

(attribute_item
  [
    "#"
    "["
    "]"
  ] @attribute)

(inner_attribute_item
  [
    "#"
    "!"
    "["
    "]"
  ] @attribute)

;; Unify Rust lifetimes ('a, 'static, '_) as Solarized Green (@keyword.modifier)
(lifetime
  (identifier) @keyword.modifier)

;; Module path qualifiers in code (e.g. fmt::Result, std::io::Error) remain calm Base0 Grey (@variable #839496)
;; per AGENTS.md ("No Chromatic Noise on Scope Qualifiers"), while formal `mod` and `use` declarations remain Violet (@module).
(scoped_identifier
  path: (identifier) @variable
  (#lua-match? @variable "^[a-z]")
  (#set! "priority" 105))
(scoped_type_identifier
  path: (identifier) @variable
  (#lua-match? @variable "^[a-z]")
  (#set! "priority" 105))
(use_declaration
  argument: (scoped_identifier
    path: (identifier) @module
    (#set! "priority" 110)))
(use_declaration
  argument: (scoped_identifier
    path: (scoped_identifier
      path: (identifier) @module
      name: (identifier) @module)
    (#set! "priority" 110)))
(use_declaration
  argument: (scoped_use_list
    path: (identifier) @module
    (#set! "priority" 110)))
(use_declaration
  argument: (scoped_use_list
    path: (scoped_identifier
      path: (identifier) @module
      name: (identifier) @module)
    (#set! "priority" 110)))

;; Wildcard pattern `_` remains calm Base0 Grey (@variable #839496)
("_" @variable
  (#set! "priority" 105))

;; Macro invocation bang `!` and tuple-variant constructors (Some, Ok, Err) remain calm Base0 Grey,
;; while the unit sentinel `None` is highlighted in Solarized Magenta (@constant.builtin #d33682) per AGENTS.md
(macro_invocation
  "!" @punctuation.delimiter
  (#set! "priority" 105))
([
  (identifier)
  (type_identifier)
] @type
  (#any-of? @type "Some" "Ok" "Err")
  (#set! "priority" 105))
([
  (identifier)
  (type_identifier)
] @constant.builtin
  (#eq? @constant.builtin "None")
  (#set! "priority" 105))

