;; extends

; =============================================================================
; Solarized Dark TrueColor Overrides for Swift (Exact 1:1 Parity with Bat)
; =============================================================================

; 1. Module Imports (Solarized Violet #6C71C4)
(import_declaration
  (identifier
    (simple_identifier) @module
    (#set! priority 120)))

; 2. Built-in Scalar Primitive Types (Solarized Green #859900)
; Domain and framework types (UUID, Date, Error, Sendable, Equatable, Codable, etc.)
; remain in calm Base0 Grey (@type #839496).
((type_identifier) @type.builtin
  (#any-of? @type.builtin
    "Bool" "Int" "Int8" "Int16" "Int32" "Int64"
    "UInt" "UInt8" "UInt16" "UInt32" "UInt64"
    "Float" "Float16" "Float32" "Float64" "Double"
    "Character" "String" "StaticString" "Substring"
    "Void" "Never" "Any" "AnyObject")
  (#set! priority 115))

; 3. Unified Attributes (@available, @MainActor, @Sendable, @discardableResult) in Solarized Violet (#6C71C4)
(attribute
  "@" @attribute
  (user_type
    (type_identifier) @attribute)
  (#set! priority 115))

; 4. Declaration & Structural Keywords (Solarized Green #859900)
(init_declaration
  "init" @keyword.function
  (#set! priority 110))

[
  "actor"
  "associatedtype"
  "macro"
] @keyword.type

[
  "is"
  "as"
  (as_operator)
] @keyword.operator

; 5. Control Flow & Exception Pathways (Solarized Yellow #B58900)
; Upstream parses `defer { ... }` as a call_expression on simple_identifier "defer".
((call_expression
  (simple_identifier) @keyword.conditional)
  (#eq? @keyword.conditional "defer")
  (#set! priority 115))

((simple_identifier) @keyword.conditional
  (#eq? @keyword.conditional "defer")
  (#set! priority 115))

; Upstream parses `fallthrough` inside switch statement bodies as a simple_identifier.
((simple_identifier) @keyword.conditional
  (#eq? @keyword.conditional "fallthrough")
  (#set! priority 115))

(switch_entry
  "case" @keyword.conditional
  (#set! priority 110))

(switch_entry
  "fallthrough" @keyword.conditional
  (#set! priority 110))

(switch_entry
  (default_keyword) @keyword.conditional
  (#set! priority 110))

(else) @keyword.conditional
(#set! priority 110)

(throws) @keyword.exception
(#set! priority 110)

; 6. Constants, Shorthand Closure Parameters & Wildcards
((simple_identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 115))

((simple_identifier) @variable.builtin
  (#lua-match? @variable.builtin "^%$[0-9]+$")
  (#set! priority 115))

(wildcard_pattern) @variable
(#set! priority 115)

; 7. Compiler Directives (#if, #else, #elseif, #endif, canImport, #available, #unavailable) in Solarized Orange (#CB4B16)
(directive) @keyword.directive

(availability_condition
  "#" @keyword.directive
  [
    "available"
    "unavailable"
  ] @keyword.directive
  (#set! priority 115))

(availability_condition
  [
    "("
    ")"
  ] @punctuation.bracket
  (#set! priority 115))

(availability_condition
  "," @punctuation.delimiter
  (#set! priority 115))

(availability_condition
  "*" @operator
  (#set! priority 115))

(availability_condition
  (identifier
    (simple_identifier) @variable)
  (#set! priority 115))

(availability_condition
  (integer_literal) @number
  (#set! priority 115))

(availability_condition
  (integer_literal)
  "." @number.float
  (integer_literal)
  (#set! priority 115))

; Unify version number dots inside @available(macOS 14.0, iOS 17.0, *) as Solarized Magenta (#D33682)
(attribute
  (integer_literal)
  "." @number.float
  (integer_literal)
  (#set! priority 115))

; 8. String Interpolation Delimiters \( and ) in Base0 Grey (#839496)
(line_string_literal
  [
    "\\("
    ")"
  ] @punctuation.special
  (#set! priority 115))

(multi_line_string_literal
  [
    "\\("
    ")"
  ] @punctuation.special
  (#set! priority 115))
