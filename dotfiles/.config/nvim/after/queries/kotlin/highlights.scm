;; extends

; =============================================================================
; Solarized Dark TrueColor Overrides for Kotlin (Exact 1:1 Parity with Bat)
; =============================================================================

; 1. Imports & Package Declarations
; Keep package path segments and imported functions in import headers in calm Base0 Grey (#839496).
; Upstream highlights trailing lowercase import segments as @function (Blue).
(import_header
  (identifier
    (simple_identifier) @variable
    (#set! priority 115)))

(import_header
  (import_alias
    (type_identifier) @type
    (#set! priority 115)))

; Wildcard import '*' in Solarized Magenta (@constant.builtin #D33682) matching Java/Rust
(wildcard_import) @constant.builtin
(#set! priority 115)

; 2. Built-in Scalar Primitives vs. Generic Container Types
; Upstream captures collection interfaces (List, Map, Set, Array, etc.) as @type.builtin (Green).
; Demote generic container types back to @type (calm Base0 Grey #839496) per Tier 1 Monotone Ground.
((type_identifier) @type
  (#any-of? @type
    "Array" "Map" "Set" "List" "EmptyMap" "EmptySet" "EmptyList"
    "MutableMap" "MutableSet" "MutableList")
  (#set! priority 115))

; Promote Kotlin core scalar/root/bottom types (Unit, Nothing, Any) to @type.builtin (Green #859900).
((type_identifier) @type.builtin
  (#any-of? @type.builtin "Unit" "Nothing" "Any")
  (#set! priority 115))

; 3. Unified Annotations (@file:JvmName, @JvmInline)
; Prevent ':' or constructor-style annotation invocations from fracturing to Base0 Grey.
(file_annotation
  "@" @attribute
  "file" @attribute
  ":" @attribute
  (#set! priority 115))

(file_annotation
  (user_type
    (type_identifier) @attribute)
  (#set! priority 115))

(file_annotation
  (constructor_invocation
    (user_type
      (type_identifier) @attribute))
  (#set! priority 115))

(annotation
  "@" @attribute
  (use_site_target)? @attribute
  (#set! priority 115))

(annotation
  (user_type
    (type_identifier) @attribute)
  (#set! priority 115))

(annotation
  (constructor_invocation
    (user_type
      (type_identifier) @attribute))
  (#set! priority 115))

; 4. Structural & Declaration Keywords (Solarized Green #859900)
(getter
  "get" @keyword.function
  (#set! priority 110))

(setter
  "set" @keyword.function
  (#set! priority 110))

(secondary_constructor
  "constructor" @keyword.function
  (#set! priority 110))

"constructor" @keyword.function

(anonymous_initializer
  "init" @keyword.function
  (#set! priority 110))

[
  "by"
  "where"
] @keyword

; 5. Control Flow vs. Word Operators
; Loop 'in' inside for statements is Control Flow Yellow (@keyword.repeat #B58900).
(for_statement
  "in" @keyword.repeat
  (#set! priority 115))

; Type/range word operators (is, !is, in, !in, as, as?) are Solarized Green (@keyword.operator #859900).
[
  "is"
  "in"
  "as"
  "as?"
] @keyword.operator

(check_expression
  [
    "!"
    "is"
    "in"
  ] @keyword.operator
  (#set! priority 115))

; 6. String Interpolation ($ident and ${expr})
; Replace upstream @none transparent fallthrough with explicit Base0 Grey captures (#839496).
(string_literal
  (interpolation_identifier_start) @punctuation.special
  (#set! priority 115))

(string_literal
  (interpolated_identifier) @variable
  (#set! priority 115))

(string_literal
  (interpolation_expression_start) @punctuation.special
  (#set! priority 115))

(string_literal
  (interpolation_expression_end) @punctuation.special
  (#set! priority 115))
