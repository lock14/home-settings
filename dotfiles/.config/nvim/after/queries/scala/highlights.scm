;; extends

; =============================================================================
; Solarized Dark Scala 3 Highlighting Architecture
; =============================================================================
; Enforce the strict Solarized Dark hierarchy:
;   - Violet (#6C71C4): import keyword, package declaration target path, and @annotations
;   - Blue (#268BD2):   Method declarations (def <name>)
;   - Green (#859900):  Structural keywords (package, class, trait, object, enum, case class/object,
;                       extends, derives, given, using, extension, val, var, def, override,
;                       sealed, final, private, protected, lazy, new) and built-in primitive types
;   - Yellow (#B58900): Control flow (if, then, else, match, pattern-matching case, for, yield,
;                       do, while, return, try, catch, finally, throw)
;   - Cyan (#2AA198):   String literals and string interpolator prefix (s"...", f"...", raw"...")
;   - Magenta (#D33682): Numeric literals, booleans, null, this, super, None, Nil, wildcard (_/*),
;                       and SCREAMING_SNAKE_CASE constants
;   - Base0 (#839496):  User types, collection types (List, Map, Option), variables, calls,
;                       and interpolated variables/expressions
; =============================================================================

; Package keyword in Green, declared package path in Violet
(package_clause
  "package" @keyword
  (#set! priority 115))

(package_clause
  (package_identifier
    (identifier) @module
    (#set! priority 115)))

; Keep lowercase import path qualifiers in calm Base0 Grey (Rule 9)
(import_declaration
  path: (identifier) @variable
  (#lua-match? @variable "^[a-z]")
  (#set! priority 115))

(stable_identifier
  (identifier) @variable
  (#lua-match? @variable "^[a-z]")
  (#set! priority 115))

; Import wildcards (* and _) and pattern wildcards (_) in Magenta
(namespace_wildcard
  [
    "*"
    "_"
  ] @constant.builtin
  (#set! priority 115))

((wildcard) @constant.builtin
  (#set! priority 115))

; Unify @annotation sigil and name in Violet (Rule 11)
(annotation
  "@" @attribute
  name: (_) @attribute
  (#set! priority 115))

; Built-in Scala scalar primitive types in Green
((type_identifier) @type.builtin
  (#any-of? @type.builtin
    "Boolean" "Byte" "Short" "Int" "Long" "Float" "Double" "Char" "String"
    "Unit" "Nothing" "Any" "AnyVal" "AnyRef" "Null")
  (#set! priority 115))

; Scala 3 braceless indented match cases and finally in Yellow control flow
(indented_cases
  (case_clause
    "case" @keyword.conditional
    (#set! priority 115)))

(case_block
  (case_clause
    "case" @keyword.conditional
    (#set! priority 115)))

("finally" @keyword.exception
  (#set! priority 115))

; Built-in singleton sentinels, self/super references, and SCREAMING_SNAKE_CASE constants in Magenta
((identifier) @constant.builtin
  (#any-of? @constant.builtin "None" "Nil")
  (#set! priority 115))

((identifier) @variable.builtin
  (#any-of? @variable.builtin "this" "super")
  (#set! priority 115))

((identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 115))

; Prevent @none transparent fallthrough inside s"..." string interpolations (Rule 35):
; Give lowercase identifiers a concrete @variable capture above @string (100),
; while keeping method declarations explicitly in Blue (#268BD2) at priority 115.
((identifier) @variable
  (#lua-match? @variable "^[a-z_]")
  (#set! priority 105))

(function_declaration
  name: (identifier) @function.method
  (#set! priority 115))

(function_definition
  name: (identifier) @function.method
  (#set! priority 115))

(interpolated_string_expression
  interpolator: (identifier) @string.special
  (#set! priority 115))

(interpolation
  "$" @punctuation.special
  (#set! priority 115))

(interpolation
  (identifier) @variable
  (#set! priority 115))

(interpolation
  (identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 120))

(interpolation
  (block
    "{" @punctuation.special
    "}" @punctuation.special)
  (#set! priority 115))
